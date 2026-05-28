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

fn parse_timeout(s: &str) -> Option<Duration> {
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

fn classify(code: Option<i32>, killed: bool) -> &'static str {
    if killed {
        return "infrastructure_error";
    }
    match code {
        Some(0) => "test_success",
        Some(1) => "test_failure",
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
/// stdout. Diagnostics go to stderr.
pub fn serve(opts: AdapterOptions) -> Result<(), String> {
    if opts.command.is_empty() {
        return Err("empty test command".into());
    }
    let stdin = std::io::stdin();
    let stdout = std::io::stdout();
    let mut out = stdout.lock();
    for line in stdin.lock().lines() {
        let line = line.map_err(|e| e.to_string())?;
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        let job: JobRequest = match serde_json::from_str(trimmed) {
            Ok(j) => j,
            Err(e) => {
                eprintln!("aps-adapter: bad job line: {e}");
                continue;
            }
        };
        let resp = run_one(&job, &opts);
        let encoded = serde_json::to_string(&resp).map_err(|e| e.to_string())?;
        writeln!(out, "{encoded}").map_err(|e| e.to_string())?;
        out.flush().map_err(|e| e.to_string())?;
    }
    Ok(())
}
