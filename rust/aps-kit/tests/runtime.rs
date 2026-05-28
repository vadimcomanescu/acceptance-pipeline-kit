use std::fs;
use std::path::PathBuf;

use aps_kit::ir::Feature;
use aps_kit::registry::{Registry, StepError};
use aps_kit::runtime::{executions_for, run_execution};

fn write_ir(path: &PathBuf, content: &str) {
    fs::write(path, content).unwrap();
}

fn calculator_ir() -> &'static str {
    r#"{
        "name": "Calc",
        "background": [{"keyword": "Given", "text": "fresh"}],
        "scenarios": [{
            "name": "addition",
            "steps": [
                {"keyword": "When", "text": "I add <a> and <b>", "parameters": ["a","b"]},
                {"keyword": "Then", "text": "result is <sum>", "parameters": ["sum"]}
            ],
            "examples": [{"a":"1","b":"2","sum":"3"}]
        }]
    }"#
}

#[test]
fn runs_scenario_with_background() {
    let tmp = tempdir();
    let path = tmp.path().join("ir.json");
    write_ir(&path, calculator_ir());

    let reg = Registry::new();
    reg.step("fresh", |w, _ex| {
        w.as_object_mut().unwrap().insert("total".into(), 0.into());
        Ok(())
    });
    reg.step("I add <a> and <b>", |w, ex| {
        let a: i64 = ex["a"].parse().unwrap();
        let b: i64 = ex["b"].parse().unwrap();
        w.as_object_mut().unwrap().insert("total".into(), (a + b).into());
        Ok(())
    });
    reg.step("result is <sum>", |w, ex| {
        let want: i64 = ex["sum"].parse().unwrap();
        let got = w["total"].as_i64().unwrap();
        if got != want {
            return Err(StepError::Failure(format!("got {got} want {want}")));
        }
        Ok(())
    });
    run_execution(&path, 0, 0, Some(&reg)).unwrap();
}

#[test]
fn unsupported_step_returns_error() {
    let tmp = tempdir();
    let path = tmp.path().join("ir.json");
    write_ir(&path, calculator_ir());
    let reg = Registry::new();
    let err = run_execution(&path, 0, 0, Some(&reg)).unwrap_err();
    assert!(matches!(err, StepError::Unsupported(_)));
}

#[test]
fn missing_parameter_returns_error() {
    let tmp = tempdir();
    let path = tmp.path().join("ir.json");
    // Same IR shape but drop `sum` from the example row.
    write_ir(
        &path,
        r#"{
            "name": "Calc",
            "background": [],
            "scenarios": [{
                "name": "s",
                "steps": [{"keyword": "Then", "text": "result is <sum>", "parameters": ["sum"]}],
                "examples": [{"a":"1"}]
            }]
        }"#,
    );
    let reg = Registry::new();
    reg.step("result is <sum>", |_w, _ex| Ok(()));
    match run_execution(&path, 0, 0, Some(&reg)).unwrap_err() {
        StepError::MissingParameter { step, param } => {
            assert_eq!(step, "result is <sum>");
            assert_eq!(param, "sum");
        }
        other => panic!("expected MissingParameter, got {other:?}"),
    }
}

#[test]
fn scenario_without_examples_runs_once_with_empty_example() {
    let tmp = tempdir();
    let path = tmp.path().join("ir.json");
    write_ir(
        &path,
        r#"{
            "name": "F",
            "scenarios": [{
                "name": "no examples",
                "steps": [{"keyword": "Then", "text": "ok"}],
                "examples": []
            }]
        }"#,
    );
    let reg = Registry::new();
    let invoked = std::sync::atomic::AtomicUsize::new(0);
    let invoked_ptr: &'static _ = Box::leak(Box::new(invoked));
    reg.step("ok", move |_w, ex| {
        assert!(ex.is_empty());
        invoked_ptr.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        Ok(())
    });
    run_execution(&path, 0, 0, Some(&reg)).unwrap();
    assert_eq!(invoked_ptr.load(std::sync::atomic::Ordering::SeqCst), 1);
}

#[test]
fn scenario_index_out_of_range_returns_failure() {
    let tmp = tempdir();
    let path = tmp.path().join("ir.json");
    write_ir(&path, calculator_ir());
    let reg = Registry::new();
    let err = run_execution(&path, 99, 0, Some(&reg)).unwrap_err();
    match err {
        StepError::Failure(msg) => assert!(msg.contains("out of range")),
        other => panic!("expected Failure, got {other:?}"),
    }
}

#[test]
fn scenario_without_examples_rejects_nonzero_index() {
    let tmp = tempdir();
    let path = tmp.path().join("ir.json");
    write_ir(
        &path,
        r#"{"name":"F","scenarios":[{"name":"s","steps":[],"examples":[]}]}"#,
    );
    let reg = Registry::new();
    let err = run_execution(&path, 0, 1, Some(&reg)).unwrap_err();
    if let StepError::Failure(msg) = err {
        assert!(msg.contains("only exampleIndex=0 is valid"));
    } else {
        panic!("expected Failure variant");
    }
}

#[test]
fn example_index_out_of_range() {
    let tmp = tempdir();
    let path = tmp.path().join("ir.json");
    write_ir(
        &path,
        r#"{"name":"F","scenarios":[{"name":"s","steps":[{"keyword":"Then","text":"ok"}],"examples":[{"a":"1"}]}]}"#,
    );
    let reg = Registry::new();
    reg.step("ok", |_w, _ex| Ok(()));
    let err = run_execution(&path, 0, 5, Some(&reg)).unwrap_err();
    if let StepError::Failure(msg) = err {
        assert!(msg.contains("out of range"));
    } else {
        panic!("expected Failure variant");
    }
}

#[test]
fn load_failure_propagates() {
    let tmp = tempdir();
    let reg = Registry::new();
    let err = run_execution(tmp.path().join("missing.json"), 0, 0, Some(&reg)).unwrap_err();
    assert!(matches!(err, StepError::Failure(_)));
}

#[test]
fn executions_for_covers_both_branches() {
    let feature: Feature = serde_json::from_str(
        r#"{
            "name": "F",
            "scenarios": [
                {"name": "with examples", "steps": [], "examples": [{"a":"1"},{"a":"2"}]},
                {"name": "no examples", "steps": [], "examples": []}
            ]
        }"#,
    )
    .unwrap();
    let got = executions_for(&feature);
    assert_eq!(got, vec![(0, 0), (0, 1), (1, 0)]);
}

// --- inline tempdir helper (avoids the tempfile dependency) ---
struct TempDir(std::path::PathBuf);
impl TempDir {
    fn path(&self) -> &std::path::Path {
        &self.0
    }
}
impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}
fn tempdir() -> TempDir {
    let mut p = std::env::temp_dir();
    p.push(format!(
        "aps-kit-test-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    std::fs::create_dir_all(&p).unwrap();
    TempDir(p)
}
