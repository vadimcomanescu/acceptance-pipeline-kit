package apskit

import (
	"bytes"
	"encoding/json"
	"strings"
	"testing"
	"time"
)

func TestParseTimeout(t *testing.T) {
	cases := []struct {
		in   string
		want time.Duration
	}{
		{"30s", 30 * time.Second},
		{"250ms", 250 * time.Millisecond},
		{"2m", 2 * time.Minute},
		{"15", 15 * time.Second},
	}
	for _, c := range cases {
		if got := parseTimeout(c.in); got != c.want {
			t.Errorf("parseTimeout(%q) = %v, want %v", c.in, got, c.want)
		}
	}
	if parseTimeout("") != 0 {
		t.Errorf("empty timeout should yield zero")
	}
	if parseTimeout("forever") != 0 {
		t.Errorf("unparseable timeout should yield zero")
	}
}

func TestClassifyExit(t *testing.T) {
	if classifyExit(0, false) != "test_success" {
		t.Error("exit 0 must be test_success")
	}
	if classifyExit(1, false) != "test_failure" {
		t.Error("exit 1 must be test_failure")
	}
	if classifyExit(42, false) != "infrastructure_error" {
		t.Error("other exits must be infrastructure_error")
	}
	if classifyExit(0, true) != "infrastructure_error" {
		t.Error("killed=true must always be infrastructure_error")
	}
}

func TestServeRunsJobs(t *testing.T) {
	// Use /bin/true and /bin/false as portable, deterministic test commands.
	jobs := strings.Join([]string{
		`{"id":"ok","feature_json":"/x","timeout":"5s"}`,
		`{"id":"fail","feature_json":"/x","timeout":"5s"}`,
	}, "\n") + "\n"
	in := strings.NewReader(jobs)
	stdoutOK := &bytes.Buffer{}
	stderr := &bytes.Buffer{}
	if err := Serve(AdapterOptions{
		Command: []string{"/bin/true"},
		Stdin:   in,
		Stdout:  stdoutOK,
		Stderr:  stderr,
	}); err != nil {
		t.Fatal(err)
	}
	lines := bytes.Split(bytes.TrimSpace(stdoutOK.Bytes()), []byte("\n"))
	if len(lines) != 2 {
		t.Fatalf("expected 2 responses, got %d", len(lines))
	}
	for _, line := range lines {
		var resp JobResponse
		if err := json.Unmarshal(line, &resp); err != nil {
			t.Fatalf("bad response JSON: %v", err)
		}
		if resp.Outcome != "test_success" {
			t.Errorf("expected test_success, got %s", resp.Outcome)
		}
		if resp.Duration < 0 {
			t.Errorf("duration must be non-negative, got %d", resp.Duration)
		}
	}
}

func TestServeRejectsBadJSON(t *testing.T) {
	in := strings.NewReader("{not valid}\n")
	stdout := &bytes.Buffer{}
	stderr := &bytes.Buffer{}
	if err := Serve(AdapterOptions{
		Command: []string{"/bin/true"},
		Stdin:   in,
		Stdout:  stdout,
		Stderr:  stderr,
	}); err != nil {
		t.Fatal(err)
	}
	if stdout.Len() != 0 {
		t.Error("stdout must be empty for bad JSON")
	}
	if !strings.Contains(stderr.String(), "bad job line") {
		t.Errorf("expected diagnostic in stderr, got %q", stderr.String())
	}
}

func TestServeSkipsBlankLines(t *testing.T) {
	in := strings.NewReader("\n   \n" + `{"id":"x","feature_json":"/x"}` + "\n\n")
	stdout := &bytes.Buffer{}
	if err := Serve(AdapterOptions{
		Command: []string{"/bin/true"},
		Stdin:   in,
		Stdout:  stdout,
		Stderr:  &bytes.Buffer{},
	}); err != nil {
		t.Fatal(err)
	}
	lines := bytes.Split(bytes.TrimSpace(stdout.Bytes()), []byte("\n"))
	if len(lines) != 1 {
		t.Errorf("expected 1 response, got %d", len(lines))
	}
}

func TestServeRequiresCommand(t *testing.T) {
	if err := Serve(AdapterOptions{}); err == nil {
		t.Fatal("expected error for empty command")
	}
}

func TestServeClassifiesFailureExit(t *testing.T) {
	in := strings.NewReader(`{"id":"x","feature_json":"/x"}` + "\n")
	stdout := &bytes.Buffer{}
	_ = Serve(AdapterOptions{
		Command: []string{"/bin/false"},
		Stdin:   in,
		Stdout:  stdout,
		Stderr:  &bytes.Buffer{},
	})
	var resp JobResponse
	if err := json.Unmarshal(bytes.TrimSpace(stdout.Bytes()), &resp); err != nil {
		t.Fatal(err)
	}
	if resp.Outcome != "test_failure" {
		t.Errorf("expected test_failure for exit 1, got %s", resp.Outcome)
	}
}

func TestAppendErrorBothBranches(t *testing.T) {
	// Regression (mutate4go): both branches of appendError need a test or a
	// flipped condition (== "" vs != "") survives unchanged.
	if got := appendError("", "msg"); got != "msg" {
		t.Errorf("empty existing: got %q, want %q", got, "msg")
	}
	if got := appendError("prefix", "msg"); got != "prefix\nmsg" {
		t.Errorf("non-empty existing: got %q, want %q", got, "prefix\nmsg")
	}
}

func TestServeClassifiesTimeout(t *testing.T) {
	in := strings.NewReader(`{"id":"x","feature_json":"/x","timeout":"100ms"}` + "\n")
	stdout := &bytes.Buffer{}
	_ = Serve(AdapterOptions{
		Command: []string{"/bin/sleep", "2"},
		Stdin:   in,
		Stdout:  stdout,
		Stderr:  &bytes.Buffer{},
	})
	var resp JobResponse
	_ = json.Unmarshal(bytes.TrimSpace(stdout.Bytes()), &resp)
	if resp.Outcome != "infrastructure_error" {
		t.Errorf("expected infrastructure_error for timeout, got %s", resp.Outcome)
	}
	// Regression (mutate4go): the killed flag set on DeadlineExceeded is what
	// triggers the "process killed or timed out" diagnostic appended to the
	// error. Without the flag the diagnostic gets dropped.
	if !strings.Contains(resp.Error, "process killed or timed out") {
		t.Errorf("expected timeout diagnostic in error, got %q", resp.Error)
	}
}

func TestServeReportsSpawnFailureAsInfrastructureError(t *testing.T) {
	in := strings.NewReader(`{"id":"x","feature_json":"/x"}` + "\n")
	stdout := &bytes.Buffer{}
	_ = Serve(AdapterOptions{
		Command: []string{"/this/does/not/exist"},
		Stdin:   in,
		Stdout:  stdout,
		Stderr:  &bytes.Buffer{},
	})
	var resp JobResponse
	_ = json.Unmarshal(bytes.TrimSpace(stdout.Bytes()), &resp)
	if resp.Outcome != "infrastructure_error" {
		t.Errorf("expected infrastructure_error for missing binary, got %s", resp.Outcome)
	}
}
