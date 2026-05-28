use std::io::{BufRead, Write};
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize)]
pub struct JobRequest {
    pub id: String,
    pub feature_json: String,
    #[serde(default)]
    pub generated_dir: String,
    #[serde(default)]
    pub work_dir: String,
    #[serde(default)]
    pub timeout: String,
}

#[derive(Debug, Serialize)]
pub struct JobResponse {
    pub id: String,
    pub outcome: String,
    pub output: String,
    pub error: String,
    pub duration: u128,
}

// Public so unit tests can pin duration parsing without subprocess setup.
pub fn parse_timeout(s: &str) -> Option<Duration> {
    let trimmed = s.trim();
    if trimmed.is_empty() {
        return None;
    }
    if let Some(rest) = trimmed.strip_suffix("ms") {
        return rest.parse::<f64>().ok().map(Duration::from_secs_f64).map(|d| d / 1000);
    }
    if let Some(rest) = trimmed.strip_suffix('s') {
        return rest.parse::<f64>().ok().map(Duration::from_secs_f64);
    }
    if let Some(rest) = trimmed.strip_suffix('m') {
        return rest.parse::<f64>().ok().map(|v| Duration::from_secs_f64(v * 60.0));
    }
    trimmed.parse::<f64>().ok().map(Duration::from_secs_f64)
}

// Public so unit tests can pin classification semantics without subprocess setup.
//
// Spec contract: exit 0 = test_success, anything that *runs and fails* is
// test_failure, anything that can't run is infrastructure_error.
//
// For Rust we have to handle two exit codes for "ran and failed":
//   1   — the conventional Unix convention.
//   101 — what `cargo test` actually returns. libtest's harness exits with
//         101 on assertion failure and cargo propagates it verbatim. Without
//         this branch the mutator misclassifies every killed mutation as
//         an infrastructure_error.
//
// Compile errors from cargo also exit 101, so a broken build can look like
// "all mutations killed" in the report. In practice the normal acceptance
// run catches that case first (it fails to compile before mutation starts).
pub fn classify(code: Option<i32>, killed: bool) -> &'static str {
    if killed {
        return "infrastructure_error";
    }
    match code {
        Some(0) => "test_success",
        Some(1) | Some(101) => "test_failure",
        _ => "infrastructure_error",
    }
}

pub struct AdapterOptions {
    pub command: Vec<String>,
    pub cwd: Option<PathBuf>,
}

fn run_one(job: &JobRequest, opts: &AdapterOptions) -> JobResponse {
    let timeout = parse_timeout(&job.timeout);
    let start = Instant::now();
    let mut command = Command::new(&opts.command[0]);
    command
        .args(&opts.command[1..])
        .env("APS_IR_PATH", &job.feature_json)
        .env("APS_GENERATED_DIR", &job.generated_dir)
        .env("APS_WORK_DIR", &job.work_dir)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    if let Some(cwd) = &opts.cwd {
        command.current_dir(cwd);
    }
    let mut child = match command.spawn() {
        Ok(c) => c,
        Err(e) => {
            return JobResponse {
                id: job.id.clone(),
                outcome: "infrastructure_error".into(),
                output: String::new(),
                error: format!("spawn failed: {e}"),
                duration: start.elapsed().as_nanos(),
            };
        }
    };

    let status_result = if let Some(timeout) = timeout {
        wait_with_timeout(&mut child, timeout)
    } else {
        child.wait().map(|s| (s, false))
    };

    let mut output = String::new();
    let mut error = String::new();
    if let Some(mut stdout) = child.stdout.take() {
        use std::io::Read;
        let _ = stdout.read_to_string(&mut output);
    }
    if let Some(mut stderr) = child.stderr.take() {
        use std::io::Read;
        let _ = stderr.read_to_string(&mut error);
    }

    match status_result {
        Ok((status, killed)) => JobResponse {
            id: job.id.clone(),
            outcome: classify(status.code(), killed).into(),
            output,
            error,
            duration: start.elapsed().as_nanos(),
        },
        Err(e) => JobResponse {
            id: job.id.clone(),
            outcome: "infrastructure_error".into(),
            output,
            error: format!("{error}\nwait: {e}"),
            duration: start.elapsed().as_nanos(),
        },
    }
}

fn wait_with_timeout(
    child: &mut std::process::Child,
    timeout: Duration,
) -> std::io::Result<(std::process::ExitStatus, bool)> {
    let start = Instant::now();
    loop {
        match child.try_wait()? {
            Some(status) => return Ok((status, false)),
            None => {
                if start.elapsed() >= timeout {
                    let _ = child.kill();
                    let status = child.wait()?;
                    return Ok((status, true));
                }
                std::thread::sleep(Duration::from_millis(50));
            }
        }
    }
}

/// Loops reading NDJSON job requests from stdin and writing NDJSON responses to
/// stdout. Diagnostics go to stderr. Thin shell over `serve_io` so the binary
/// has no logic the tests can't reach.
pub fn serve(opts: AdapterOptions) -> Result<(), String> {
    let stdin = std::io::stdin();
    let stdout = std::io::stdout();
    let stderr = std::io::stderr();
    serve_io(opts, stdin.lock(), stdout.lock(), stderr.lock())
}

/// `serve` with injected I/O. Reads NDJSON job requests from `input`, writes
/// NDJSON responses to `output`, and routes diagnostics to `diagnostics`.
/// Tests drive this directly with byte vectors so the protocol behaviour is
/// fully covered.
pub fn serve_io<R, W, E>(
    opts: AdapterOptions,
    input: R,
    mut output: W,
    mut diagnostics: E,
) -> Result<(), String>
where
    R: BufRead,
    W: Write,
    E: Write,
{
    if opts.command.is_empty() {
        return Err("empty test command".into());
    }
    for line in input.lines() {
        let line = line.map_err(|e| e.to_string())?;
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        let job: JobRequest = match serde_json::from_str(trimmed) {
            Ok(j) => j,
            Err(e) => {
                writeln!(diagnostics, "aps-adapter: bad job line: {e}").ok();
                continue;
            }
        };
        let resp = run_one(&job, &opts);
        let encoded = serde_json::to_string(&resp).map_err(|e| e.to_string())?;
        writeln!(output, "{encoded}").map_err(|e| e.to_string())?;
        output.flush().map_err(|e| e.to_string())?;
    }
    Ok(())
}
