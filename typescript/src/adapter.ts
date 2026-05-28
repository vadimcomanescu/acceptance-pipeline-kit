// Runner adapter: persistent NDJSON worker for gherkin-mutator.
import { spawnSync } from "node:child_process";
import { createInterface } from "node:readline";
import type { Readable, Writable } from "node:stream";

interface JobRequest {
  id: string;
  feature_json: string;
  generated_dir?: string;
  work_dir?: string;
  timeout?: string;
}

interface JobResponse {
  id: string;
  outcome: "test_success" | "test_failure" | "infrastructure_error";
  output: string;
  error: string;
  duration: number;
}

// Public so tests pin classification semantics without subprocess setup.
export function classifyExit(
  status: number | null,
): JobResponse["outcome"] {
  // Spec contract: exit 0 = test_success, exit 1 = test_failure, anything
  // else (including timeout) = infrastructure_error.
  if (status === 0) return "test_success";
  if (status === 1) return "test_failure";
  return "infrastructure_error";
}

// Public so tests pin duration parsing without subprocess setup.
export function parseTimeoutMs(s: string | undefined): number | undefined {
  if (!s) return undefined;
  const trimmed = s.trim();
  if (trimmed.endsWith("ms")) return Number(trimmed.slice(0, -2));
  if (trimmed.endsWith("s")) return Number(trimmed.slice(0, -1)) * 1000;
  if (trimmed.endsWith("m")) return Number(trimmed.slice(0, -1)) * 60_000;
  const n = Number(trimmed);
  return Number.isFinite(n) ? n * 1000 : undefined;
}

export interface ServeOptions {
  command: string;
  args: string[];
  cwd?: string;
}

/** Real-world entry point: uses process.stdin / stdout / stderr. */
export async function serve(opts: ServeOptions): Promise<void> {
  await serveIO(opts, process.stdin, process.stdout, process.stderr);
}

/** Testable entry point: takes injectable streams so unit tests can drive
 *  the NDJSON protocol in-process. */
export async function serveIO(
  opts: ServeOptions,
  input: Readable,
  output: Writable,
  diagnostics: Writable,
): Promise<void> {
  const rl = createInterface({ input });
  for await (const line of rl) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    let job: JobRequest;
    try {
      job = JSON.parse(trimmed);
    } catch (err) {
      diagnostics.write(
        `aps-adapter: bad job line: ${(err as Error).message}\n`,
      );
      continue;
    }
    const response = runOne(job, opts);
    output.write(JSON.stringify(response) + "\n");
  }
}

function runOne(job: JobRequest, opts: ServeOptions): JobResponse {
  const start = process.hrtime.bigint();
  const env = {
    ...process.env,
    APS_IR_PATH: job.feature_json,
    APS_GENERATED_DIR: job.generated_dir ?? "",
    APS_WORK_DIR: job.work_dir ?? "",
  };
  const proc = spawnSync(opts.command, opts.args, {
    env,
    cwd: opts.cwd,
    encoding: "utf-8",
    timeout: parseTimeoutMs(job.timeout),
  });
  const duration = Number(process.hrtime.bigint() - start);
  if (proc.error && proc.signal === "SIGTERM") {
    return {
      id: job.id,
      outcome: "infrastructure_error",
      output: proc.stdout ?? "",
      error: `timeout: ${proc.error.message}`,
      duration,
    };
  }
  if (proc.error) {
    return {
      id: job.id,
      outcome: "infrastructure_error",
      output: proc.stdout ?? "",
      error: proc.error.message,
      duration,
    };
  }
  return {
    id: job.id,
    outcome: classifyExit(proc.status),
    output: proc.stdout ?? "",
    error: proc.stderr ?? "",
    duration,
  };
}
