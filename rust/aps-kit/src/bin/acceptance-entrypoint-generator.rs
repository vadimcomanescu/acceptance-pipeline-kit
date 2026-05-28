// acceptance-entrypoint-generator: APS-conformant generator for Rust projects.
//
// Usage:
//     acceptance-entrypoint-generator <json-ir> <generated-test-output>
//
// Configuration via env vars:
//     APS_FEATURE_PATH    feature path to record in metadata (default: <json-ir>)
//     APS_HANDLERS_CRATE  crate name to import for handlers (default: handlers)
use std::process::ExitCode;

use aps_kit::cli::run_generate;

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let code = run_generate(&args, &mut std::io::stderr());
    ExitCode::from(code as u8)
}
