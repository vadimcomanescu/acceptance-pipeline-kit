package apskit

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

// JobRequest is one mutator->adapter message.
type JobRequest struct {
	ID           string `json:"id"`
	FeatureJSON  string `json:"feature_json"`
	GeneratedDir string `json:"generated_dir,omitempty"`
	WorkDir      string `json:"work_dir,omitempty"`
	Timeout      string `json:"timeout,omitempty"`
}

// JobResponse is one adapter->mutator message.
type JobResponse struct {
	ID       string `json:"id"`
	Outcome  string `json:"outcome"`
	Output   string `json:"output"`
	Error    string `json:"error"`
	Duration int64  `json:"duration"`
}

func parseTimeout(s string) time.Duration {
	s = strings.TrimSpace(s)
	if s == "" {
		return 0
	}
	switch {
	case strings.HasSuffix(s, "ms"):
		if v, err := strconv.ParseFloat(strings.TrimSuffix(s, "ms"), 64); err == nil {
			return time.Duration(v * float64(time.Millisecond))
		}
	case strings.HasSuffix(s, "s"):
		if v, err := strconv.ParseFloat(strings.TrimSuffix(s, "s"), 64); err == nil {
			return time.Duration(v * float64(time.Second))
		}
	case strings.HasSuffix(s, "m"):
		if v, err := strconv.ParseFloat(strings.TrimSuffix(s, "m"), 64); err == nil {
			return time.Duration(v * float64(time.Minute))
		}
	default:
		if v, err := strconv.ParseFloat(s, 64); err == nil {
			return time.Duration(v * float64(time.Second))
		}
	}
	return 0
}

func classifyExit(code int, killed bool) string {
	if killed {
		return "infrastructure_error"
	}
	if code == 0 {
		return "test_success"
	}
	if code == 1 {
		return "test_failure"
	}
	return "infrastructure_error"
}

// AdapterOptions configures the runner adapter loop.
type AdapterOptions struct {
	Command []string
	Cwd     string
	Stdin   io.Reader
	Stdout  io.Writer
	Stderr  io.Writer
}

func runOne(job JobRequest, opts AdapterOptions) JobResponse {
	timeout := parseTimeout(job.Timeout)
	ctx := context.Background()
	if timeout > 0 {
		var cancel context.CancelFunc
		ctx, cancel = context.WithTimeout(ctx, timeout)
		defer cancel()
	}
	cmd := exec.CommandContext(ctx, opts.Command[0], opts.Command[1:]...)
	cmd.Dir = opts.Cwd
	cmd.Env = append(
		append([]string(nil), os.Environ()...),
		"APS_IR_PATH="+job.FeatureJSON,
		"APS_GENERATED_DIR="+job.GeneratedDir,
		"APS_WORK_DIR="+job.WorkDir,
	)
	start := time.Now()
	stdout, stderr := &strings.Builder{}, &strings.Builder{}
	cmd.Stdout, cmd.Stderr = stdout, stderr
	err := cmd.Run()
	elapsed := time.Since(start).Nanoseconds()
	exitCode := 0
	killed := false
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			exitCode = exitErr.ExitCode()
		} else {
			killed = true
		}
	}
	if ctx.Err() == context.DeadlineExceeded {
		killed = true
	}
	resp := JobResponse{
		ID:       job.ID,
		Outcome:  classifyExit(exitCode, killed),
		Output:   stdout.String(),
		Error:    stderr.String(),
		Duration: elapsed,
	}
	if killed {
		resp.Error = appendError(resp.Error, "infrastructure: process killed or timed out")
	}
	return resp
}

func appendError(existing, msg string) string {
	if existing == "" {
		return msg
	}
	return existing + "\n" + msg
}

// Serve reads NDJSON job requests from opts.Stdin and writes NDJSON responses
// to opts.Stdout until EOF.
func Serve(opts AdapterOptions) error {
	if len(opts.Command) == 0 {
		return fmt.Errorf("Serve: empty command")
	}
	in := bufio.NewScanner(opts.Stdin)
	in.Buffer(make([]byte, 1<<20), 1<<24)
	for in.Scan() {
		line := strings.TrimSpace(in.Text())
		if line == "" {
			continue
		}
		var job JobRequest
		if err := json.Unmarshal([]byte(line), &job); err != nil {
			fmt.Fprintf(opts.Stderr, "aps-adapter: bad job line: %v\n", err)
			continue
		}
		resp := runOne(job, opts)
		out, err := json.Marshal(resp)
		if err != nil {
			fmt.Fprintf(opts.Stderr, "aps-adapter: encode response: %v\n", err)
			continue
		}
		opts.Stdout.Write(out)
		opts.Stdout.Write([]byte("\n"))
	}
	return in.Err()
}

// mutate4go-manifest-begin
// {"version":1,"tested_at":"2026-05-28T18:16:05+02:00","module_hash":"d916442158a0b8329ea98b95646e0892ae4920dcd21f0751c11e7d9a45231375","functions":[{"id":"func/parseTimeout","name":"parseTimeout","line":34,"end_line":58,"hash":"a1dee0aa7d70256f2871809f0c72ae3a3e2332a1c9bd066d8bccb127c6a49201"},{"id":"func/classifyExit","name":"classifyExit","line":60,"end_line":71,"hash":"e883318c180250f7c80709370d81a48200e7f95b170c68ba192b26f1fa82d9d9"},{"id":"func/runOne","name":"runOne","line":82,"end_line":126,"hash":"dfb01cde910c13d69431145107c91f86e5137ed8ba3b2c2acc09942e2c9d6762"},{"id":"func/appendError","name":"appendError","line":128,"end_line":133,"hash":"0e408434d6860c110146560623053b4b5d11ab9d6cf25b2975e05f0f447a6de2"},{"id":"func/Serve","name":"Serve","line":137,"end_line":163,"hash":"4d273fcb51a1f715fd630d013f4b985d083cb582600b5484bf8147ebfc74e658"}]}
// mutate4go-manifest-end
