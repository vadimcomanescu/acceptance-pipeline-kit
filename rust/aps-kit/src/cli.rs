//! Library entry points for the two CLI binaries. The bins are thin shells
//! that delegate to these functions so unit tests can exercise argv parsing
//! and the spec-defined exit codes in-process.
use std::path::{Path, PathBuf};

use crate::adapter::{serve_io, AdapterOptions};
use crate::generator::{generate, GenerateOptions};

pub const GENERATE_USAGE: &str =
    "usage: acceptance-entrypoint-generator <json-ir> <generated-test-output>";
pub const ADAPTER_USAGE: &str = "usage: aps-adapter <test-cmd> [test-args...]";

/// Run the acceptance-entrypoint-generator CLI logic. Returns the spec exit
/// code: 0 success, 1 IO/generation error, 2 usage error.
pub fn run_generate(args: &[String], stderr: &mut impl std::io::Write) -> i32 {
    if matches!(args.first().map(String::as_str), Some("-h") | Some("--help")) {
        writeln!(stderr, "{GENERATE_USAGE}").ok();
        return 0;
    }
    if args.len() != 2 {
        writeln!(stderr, "{GENERATE_USAGE}").ok();
        return 2;
    }
    let feature_path = std::env::var("APS_FEATURE_PATH").ok();
    let handlers_crate =
        std::env::var("APS_HANDLERS_CRATE").unwrap_or_else(|_| "handlers".into());
    let opts = GenerateOptions {
        ir_path: Path::new(&args[0]),
        output_dir: Path::new(&args[1]),
        feature_path: feature_path.as_deref(),
        handlers_crate: &handlers_crate,
    };
    match generate(opts) {
        Ok(_) => 0,
        Err(e) => {
            writeln!(stderr, "acceptance-entrypoint-generator: {e}").ok();
            1
        }
    }
}

/// Run the aps-adapter CLI logic. Reads NDJSON jobs from `input`, writes
/// responses to `output`, diagnostics to `diagnostics`. Returns the spec
/// exit code: 0 success, 1 IO error from serve, 2 usage error.
pub fn run_adapter<R, W, E>(
    args: &[String],
    input: R,
    output: W,
    mut diagnostics: E,
) -> i32
where
    R: std::io::BufRead,
    W: std::io::Write,
    E: std::io::Write,
{
    if matches!(args.first().map(String::as_str), Some("-h") | Some("--help")) {
        writeln!(diagnostics, "{ADAPTER_USAGE}").ok();
        return 0;
    }
    if args.is_empty() {
        writeln!(diagnostics, "{ADAPTER_USAGE}").ok();
        return 2;
    }
    let opts = AdapterOptions {
        command: args.to_vec(),
        cwd: None::<PathBuf>,
    };
    // We re-bind `diagnostics` ownership: serve_io needs an owned writer.
    match serve_io(opts, input, output, &mut diagnostics) {
        Ok(()) => 0,
        Err(e) => {
            writeln!(diagnostics, "aps-adapter: {e}").ok();
            1
        }
    }
}
