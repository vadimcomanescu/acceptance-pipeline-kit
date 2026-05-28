// acceptance-entrypoint-generator: APS-conformant generator for Rust projects.
//
// Usage:
//     acceptance-entrypoint-generator <json-ir> <generated-test-output>
//
// Two positional arguments, nothing else. Configuration via env vars:
//     APS_FEATURE_PATH    feature path to record in metadata (default: <json-ir>)
//     APS_HANDLERS_CRATE  crate name to import for handlers (default: handlers)
use std::path::Path;
use std::process::ExitCode;

use aps_kit::generator::{generate, GenerateOptions};

const USAGE: &str =
    "usage: acceptance-entrypoint-generator <json-ir> <generated-test-output>";

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if matches!(args.first().map(String::as_str), Some("-h") | Some("--help")) {
        eprintln!("{USAGE}");
        return ExitCode::SUCCESS;
    }
    if args.len() != 2 {
        eprintln!("{USAGE}");
        return ExitCode::from(2);
    }
    let feature_path = std::env::var("APS_FEATURE_PATH").ok();
    let handlers_crate = std::env::var("APS_HANDLERS_CRATE").unwrap_or_else(|_| "handlers".into());
    let opts = GenerateOptions {
        ir_path: Path::new(&args[0]),
        output_dir: Path::new(&args[1]),
        feature_path: feature_path.as_deref(),
        handlers_crate: &handlers_crate,
    };
    match generate(opts) {
        Ok(_) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("acceptance-entrypoint-generator: {e}");
            ExitCode::from(1)
        }
    }
}
