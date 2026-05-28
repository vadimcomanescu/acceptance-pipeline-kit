use std::fs;
use std::path::PathBuf;

use aps_kit::ir::{load_ir, Feature};

fn write(path: &PathBuf, contents: &str) {
    fs::write(path, contents).unwrap();
}

#[test]
fn load_ir_rejects_missing_file() {
    let tmp = tempdir();
    let err = load_ir(tmp.path().join("missing.json")).unwrap_err();
    assert!(err.contains("read IR"));
}

#[test]
fn load_ir_rejects_bad_json() {
    let tmp = tempdir();
    let path = tmp.path().join("bad.json");
    write(&path, "not json");
    let err = load_ir(&path).unwrap_err();
    assert!(err.contains("decode IR"));
}

#[test]
fn load_ir_rejects_missing_name() {
    let tmp = tempdir();
    let path = tmp.path().join("noname.json");
    write(&path, r#"{"scenarios":[]}"#);
    let err = load_ir(&path).unwrap_err();
    // serde rejects the JSON during decode because `name` has no default;
    // the explicit `is_empty()` guard catches the case where name is "".
    assert!(err.contains("decode IR") || err.contains("missing 'name'"));
}

#[test]
fn load_ir_rejects_empty_name() {
    let tmp = tempdir();
    let path = tmp.path().join("emptyname.json");
    write(&path, r#"{"name":"","scenarios":[]}"#);
    let err = load_ir(&path).unwrap_err();
    assert!(err.contains("missing 'name'"));
}

#[test]
fn load_ir_round_trip() {
    let tmp = tempdir();
    let path = tmp.path().join("ir.json");
    let payload = r#"{
        "name": "Calc",
        "background": [{"keyword": "Given", "text": "ready"}],
        "scenarios": [
            {
                "name": "addition",
                "steps": [
                    {"keyword": "Then", "text": "the result is <sum>", "parameters": ["sum"]}
                ],
                "examples": [{"sum": "3"}]
            }
        ]
    }"#;
    write(&path, payload);
    let feature: Feature = load_ir(&path).unwrap();
    assert_eq!(feature.name, "Calc");
    assert_eq!(feature.background.len(), 1);
    assert_eq!(feature.scenarios.len(), 1);
    assert_eq!(feature.scenarios[0].examples[0]["sum"], "3");
}

// Lightweight tempdir helper; std doesn't have one and pulling in the
// `tempfile` crate just for tests is overkill.
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
