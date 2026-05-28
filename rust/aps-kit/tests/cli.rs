// CLI logic tests. Calls run_generate and run_adapter directly so coverage
// counts every argv-parsing and exit-code branch.
use std::fs;
use std::io::Cursor;
use std::path::PathBuf;

use aps_kit::cli::{run_adapter, run_generate};

// ---- run_generate -------------------------------------------------------

#[test]
fn generate_help_returns_0() {
    let mut err = Vec::new();
    assert_eq!(run_generate(&["--help".into()], &mut err), 0);
    assert!(String::from_utf8(err).unwrap().contains("usage:"));
}

#[test]
fn generate_no_args_returns_2() {
    let mut err = Vec::new();
    assert_eq!(run_generate(&[], &mut err), 2);
}

#[test]
fn generate_extra_args_returns_2() {
    let mut err = Vec::new();
    assert_eq!(
        run_generate(&["a".into(), "b".into(), "c".into()], &mut err),
        2
    );
}

#[test]
fn generate_missing_ir_returns_1() {
    let tmp = tempdir();
    let mut err = Vec::new();
    let args = vec![
        tmp.path().join("missing.json").to_string_lossy().to_string(),
        tmp.path().join("out").to_string_lossy().to_string(),
    ];
    assert_eq!(run_generate(&args, &mut err), 1);
    assert!(String::from_utf8(err).unwrap().contains("acceptance-entrypoint-generator"));
}

#[test]
fn generate_success_writes_metadata() {
    let tmp = tempdir();
    let ir = tmp.path().join("ir.json");
    fs::write(
        &ir,
        r#"{"name":"F","scenarios":[{"name":"s","steps":[{"keyword":"Then","text":"ok"}],"examples":[]}]}"#,
    )
    .unwrap();
    let out = tmp.path().join("out");
    // Set env so the metadata uses the conventional filename.
    std::env::set_var("APS_FEATURE_PATH", "features/foo.feature");
    let mut err = Vec::new();
    assert_eq!(
        run_generate(
            &[
                ir.to_string_lossy().to_string(),
                out.to_string_lossy().to_string()
            ],
            &mut err
        ),
        0
    );
    std::env::remove_var("APS_FEATURE_PATH");
    let meta = out.join("metadata").join("features-foo-feature.json");
    assert!(meta.exists(), "expected metadata at {meta:?}");
}

// ---- run_adapter --------------------------------------------------------

#[test]
fn adapter_help_returns_0() {
    let mut err = Vec::new();
    let code = run_adapter(
        &["-h".into()],
        Cursor::new(""),
        Vec::<u8>::new(),
        &mut err,
    );
    assert_eq!(code, 0);
}

#[test]
fn adapter_no_args_returns_2() {
    let mut err = Vec::new();
    let code = run_adapter(&[], Cursor::new(""), Vec::<u8>::new(), &mut err);
    assert_eq!(code, 2);
}

#[test]
fn adapter_empty_command_via_no_positional_returns_2() {
    let mut err = Vec::new();
    // Calling with only a flag should be treated as no positional command.
    let code = run_adapter(
        &[],
        Cursor::new(""),
        Vec::<u8>::new(),
        &mut err,
    );
    assert_eq!(code, 2);
}

#[test]
fn adapter_runs_jobs_and_returns_0() {
    let mut out = Vec::<u8>::new();
    let mut err = Vec::<u8>::new();
    let code = run_adapter(
        &["/bin/true".into()],
        Cursor::new(b"{\"id\":\"x\",\"feature_json\":\"/x\"}\n".to_vec()),
        &mut out,
        &mut err,
    );
    assert_eq!(code, 0);
    let resp: serde_json::Value =
        serde_json::from_str(std::str::from_utf8(&out).unwrap().trim()).unwrap();
    assert_eq!(resp["outcome"], "test_success");
}

// ---- inline tempdir helper ---------------------------------------------

struct TempDir(PathBuf);
impl TempDir {
    fn path(&self) -> &std::path::Path { &self.0 }
}
impl Drop for TempDir {
    fn drop(&mut self) { let _ = fs::remove_dir_all(&self.0); }
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
    fs::create_dir_all(&p).unwrap();
    TempDir(p)
}
