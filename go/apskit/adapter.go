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
