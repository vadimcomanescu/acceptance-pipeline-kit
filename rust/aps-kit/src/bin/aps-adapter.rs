// Usage: aps-adapter <test-cmd> [test-args...]
// Everything after the program name is the project's test command.
// The positional form survives gherkin-mutator's whitespace-only splitting
// of --runner-worker.
use std::process::ExitCode;

use aps_kit::adapter::{serve, AdapterOptions};

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.is_empty() || matches!(args[0].as_str(), "-h" | "--help") {
        eprintln!("usage: aps-adapter <test-cmd> [test-args...]");
        return if args.is_empty() {
            ExitCode::from(2)
        } else {
            ExitCode::SUCCESS
        };
    }
    let opts = AdapterOptions {
        command: args,
        cwd: None,
    };
    match serve(opts) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("aps-adapter: {e}");
            ExitCode::from(1)
        }
    }
}
