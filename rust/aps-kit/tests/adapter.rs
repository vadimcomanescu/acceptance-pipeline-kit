// In-process adapter tests. Drive serve_io with byte buffers so coverage
// counts every branch of the NDJSON loop and the classification code.
use std::io::Cursor;

use aps_kit::adapter::{classify, parse_timeout, serve_io, AdapterOptions};

fn drive(opts: AdapterOptions, input: &str) -> (String, String) {
    let mut out = Vec::<u8>::new();
    let mut err = Vec::<u8>::new();
    serve_io(opts, Cursor::new(input.as_bytes()), &mut out, &mut err).unwrap();
    (
        String::from_utf8(out).unwrap(),
        String::from_utf8(err).unwrap(),
    )
}

#[test]
fn parse_timeout_rejects_malformed_units() {
    // The suffix matches but the prefix isn't a number.
    assert_eq!(parse_timeout("abcms"), None);
    assert_eq!(parse_timeout("abcs"), None);
    assert_eq!(parse_timeout("abcm"), None);
}

#[test]
fn parse_timeout_units() {
    assert_eq!(
        parse_timeout("30s"),
        Some(std::time::Duration::from_secs(30))
    );
    assert_eq!(
        parse_timeout("250ms"),
        Some(std::time::Duration::from_millis(250))
    );
    assert_eq!(
        parse_timeout("2m"),
        Some(std::time::Duration::from_secs(120))
    );
    assert_eq!(
        parse_timeout("15"),
        Some(std::time::Duration::from_secs(15))
    );
    assert_eq!(parse_timeout(""), None);
    assert_eq!(parse_timeout("forever"), None);
}

#[test]
fn classify_covers_every_branch() {
    assert_eq!(classify(Some(0), false), "test_success");
    assert_eq!(classify(Some(1), false), "test_failure");
    // Regression: cargo test propagates libtest's exit code (101) on
    // assertion failure. Without recognising 101 the mutator misclassified
    // every killed mutation as an infrastructure_error.
    assert_eq!(classify(Some(101), false), "test_failure");
    assert_eq!(classify(Some(42), false), "infrastructure_error");
    assert_eq!(classify(None, false), "infrastructure_error");
    assert_eq!(classify(Some(0), true), "infrastructure_error");
}

#[test]
fn serve_io_classifies_test_success() {
    let opts = AdapterOptions {
        command: vec!["/bin/true".into()],
        cwd: None,
    };
    let (out, _err) = drive(opts, r#"{"id":"x","feature_json":"/x"}"#);
    let resp: serde_json::Value = serde_json::from_str(out.trim()).unwrap();
    assert_eq!(resp["outcome"], "test_success");
    assert_eq!(resp["id"], "x");
    assert!(resp["duration"].as_u64().unwrap() > 0);
}

#[test]
fn serve_io_classifies_test_failure() {
    let opts = AdapterOptions {
        command: vec!["/bin/false".into()],
        cwd: None,
    };
    let (out, _err) = drive(opts, r#"{"id":"f","feature_json":"/x"}"#);
    let resp: serde_json::Value = serde_json::from_str(out.trim()).unwrap();
    assert_eq!(resp["outcome"], "test_failure");
}

#[test]
fn serve_io_classifies_timeout_as_infrastructure_error() {
    let opts = AdapterOptions {
        command: vec!["/bin/sleep".into(), "2".into()],
        cwd: None,
    };
    let (out, _err) = drive(opts, r#"{"id":"t","feature_json":"/x","timeout":"100ms"}"#);
    let resp: serde_json::Value = serde_json::from_str(out.trim()).unwrap();
    assert_eq!(resp["outcome"], "infrastructure_error");
}

#[test]
fn serve_io_reports_spawn_failure_as_infrastructure_error() {
    let opts = AdapterOptions {
        command: vec!["/this/does/not/exist".into()],
        cwd: None,
    };
    let (out, _err) = drive(opts, r#"{"id":"s","feature_json":"/x"}"#);
    let resp: serde_json::Value = serde_json::from_str(out.trim()).unwrap();
    assert_eq!(resp["outcome"], "infrastructure_error");
    assert!(resp["error"].as_str().unwrap().contains("spawn failed"));
}

#[test]
fn serve_io_skips_blank_lines_and_reports_bad_json() {
    let opts = AdapterOptions {
        command: vec!["/bin/true".into()],
        cwd: None,
    };
    let (out, err) = drive(
        opts,
        "\n   \n{not valid}\n{\"id\":\"x\",\"feature_json\":\"/x\"}\n",
    );
    let lines: Vec<_> = out.lines().filter(|l| !l.is_empty()).collect();
    assert_eq!(lines.len(), 1);
    assert!(err.contains("bad job line"));
}

#[test]
fn serve_io_rejects_empty_command() {
    let result = serve_io(
        AdapterOptions { command: vec![], cwd: None },
        Cursor::new(""),
        Vec::<u8>::new(),
        Vec::<u8>::new(),
    );
    assert!(result.is_err());
}

#[test]
fn serve_io_handles_multiple_jobs_in_one_session() {
    let opts = AdapterOptions {
        command: vec!["/bin/true".into()],
        cwd: None,
    };
    let input = "\
{\"id\":\"a\",\"feature_json\":\"/x\"}\n\
{\"id\":\"b\",\"feature_json\":\"/y\"}\n\
{\"id\":\"c\",\"feature_json\":\"/z\"}\n";
    let (out, _err) = drive(opts, input);
    let lines: Vec<_> = out.lines().collect();
    assert_eq!(lines.len(), 3);
    let ids: Vec<String> = lines
        .iter()
        .map(|l| {
            let v: serde_json::Value = serde_json::from_str(l).unwrap();
            v["id"].as_str().unwrap().to_string()
        })
        .collect();
    assert_eq!(ids, vec!["a", "b", "c"]);
}

#[test]
fn serve_io_injects_aps_env_vars() {
    // /bin/sh prints APS_IR_PATH so we can see the env was set per-job.
    let opts = AdapterOptions {
        command: vec![
            "/bin/sh".into(),
            "-c".into(),
            "printf '%s' \"$APS_IR_PATH\"".into(),
        ],
        cwd: None,
    };
    let (out, _err) = drive(opts, r#"{"id":"e","feature_json":"/path/to/mutated.json"}"#);
    let resp: serde_json::Value = serde_json::from_str(out.trim()).unwrap();
    assert_eq!(resp["outcome"], "test_success");
    assert_eq!(resp["output"], "/path/to/mutated.json");
}
