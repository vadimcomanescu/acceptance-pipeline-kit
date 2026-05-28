// aps-adapter: APS-conformant runner adapter for Rust projects.
//
// Usage:
//     aps-adapter <test-cmd> [test-args...]
use std::process::ExitCode;

use aps_kit::cli::run_adapter;

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let stdin = std::io::stdin();
    let stdout = std::io::stdout();
    let stderr = std::io::stderr();
    let code = run_adapter(&args, stdin.lock(), stdout.lock(), stderr.lock());
    ExitCode::from(code as u8)
}
