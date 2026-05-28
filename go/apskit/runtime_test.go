package apskit

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

func writeIR(t *testing.T) string {
	t.Helper()
	ir := Feature{
		Name:       "Calculator",
		Background: []Step{{Keyword: "Given", Text: "a fresh calculator"}},
		Scenarios: []Scenario{{
			Name: "addition",
			Steps: []Step{
				{Keyword: "When", Text: "I add <a> and <b>", Parameters: []string{"a", "b"}},
				{Keyword: "Then", Text: "the result is <sum>", Parameters: []string{"sum"}},
			},
			Examples: []map[string]string{{"a": "1", "b": "2", "sum": "3"}},
		}},
	}
	data, err := json.Marshal(ir)
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(t.TempDir(), "ir.json")
	if err := os.WriteFile(path, data, 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestRunExecution(t *testing.T) {
	reg := NewRegistry()
	reg.Step("a fresh calculator", func(world World, _ Example) error {
		world["total"] = 0
		return nil
	})
	reg.Step("I add <a> and <b>", func(world World, ex Example) error {
		a, _ := strconv.Atoi(ex["a"])
		b, _ := strconv.Atoi(ex["b"])
		world["total"] = a + b
		return nil
	})
	reg.Step("the result is <sum>", func(world World, ex Example) error {
		want, _ := strconv.Atoi(ex["sum"])
		if world["total"] != want {
			t.Fatalf("got %v want %d", world["total"], want)
		}
		return nil
	})
	if err := RunExecution(writeIR(t), 0, 0, reg); err != nil {
		t.Fatalf("RunExecution: %v", err)
	}
}

func TestRunExecutionUnsupportedStep(t *testing.T) {
	reg := NewRegistry()
	err := RunExecution(writeIR(t), 0, 0, reg)
	var uerr *UnsupportedStepError
	if !errors.As(err, &uerr) {
		t.Fatalf("expected UnsupportedStepError, got %v", err)
	}
}

func TestRunExecutionWithNilRegistryFallsBackToDefault(t *testing.T) {
	// Register handlers in DefaultRegistry then run with nil. We use unique
	// step text to avoid colliding with other tests' default-registry state.
	DefaultRegistry.Step("fresh-default-calc", func(w World, _ Example) error {
		w["x"] = 1
		return nil
	})
	defer delete(DefaultRegistry.steps, "fresh-default-calc")
	feature := Feature{
		Name:      "F",
		Scenarios: []Scenario{{Name: "s", Steps: []Step{{Keyword: "Given", Text: "fresh-default-calc"}}}},
	}
	data, _ := json.Marshal(feature)
	path := filepath.Join(t.TempDir(), "ir.json")
	_ = os.WriteFile(path, data, 0o644)
	if err := RunExecution(path, 0, 0, nil); err != nil {
		t.Fatalf("RunExecution: %v", err)
	}
}

func TestRunExecutionScenarioIndexOutOfRange(t *testing.T) {
	reg := NewRegistry()
	reg.Step("a fresh calculator", func(World, Example) error { return nil })
	err := RunExecution(writeIR(t), 5, 0, reg)
	if err == nil || !strings.Contains(err.Error(), "out of range") {
		t.Fatalf("expected out-of-range error, got %v", err)
	}
	if err := RunExecution(writeIR(t), -1, 0, reg); err == nil {
		t.Fatal("expected negative-index error")
	}
	// Boundary: the IR has 1 scenario, so valid indices are [0]. Index 1
	// (== len) must be rejected. mutate4go found that >= -> > let this case
	// slip through and crash with an out-of-bounds slice access.
	if err := RunExecution(writeIR(t), 1, 0, reg); err == nil ||
		!strings.Contains(err.Error(), "out of range") {
		t.Fatalf("expected boundary out-of-range error, got %v", err)
	}
}

func TestRunExecutionMissingParameter(t *testing.T) {
	reg := NewRegistry()
	reg.Step("a fresh calculator", func(World, Example) error { return nil })
	reg.Step("I add <a> and <b>", func(World, Example) error { return nil })
	reg.Step("the result is <sum>", func(World, Example) error { return nil })
	// Strip "sum" from the example row.
	path := writeIR(t)
	raw, _ := os.ReadFile(path)
	var feature Feature
	_ = json.Unmarshal(raw, &feature)
	delete(feature.Scenarios[0].Examples[0], "sum")
	out, _ := json.Marshal(feature)
	_ = os.WriteFile(path, out, 0o644)
	if err := RunExecution(path, 0, 0, reg); err == nil ||
		!strings.Contains(err.Error(), "missing example value") {
		t.Fatalf("expected missing-param error, got %v", err)
	}
}

func TestRunExecutionLoadFailure(t *testing.T) {
	err := RunExecution(filepath.Join(t.TempDir(), "missing.json"), 0, 0, nil)
	if err == nil {
		t.Fatal("expected error for missing IR")
	}
}

func TestExecutionsForCoversBothBranches(t *testing.T) {
	feature := &Feature{
		Scenarios: []Scenario{
			{Name: "with examples", Examples: []map[string]string{{"a": "1"}, {"a": "2"}}},
			{Name: "no examples"},
		},
	}
	got := ExecutionsFor(feature)
	want := [][2]int{{0, 0}, {0, 1}, {1, 0}}
	if fmt.Sprintf("%v", got) != fmt.Sprintf("%v", want) {
		t.Errorf("ExecutionsFor: got %v want %v", got, want)
	}
}

func TestExampleForOutOfRange(t *testing.T) {
	scenario := Scenario{Name: "s", Examples: []map[string]string{{"a": "1"}}}
	if _, err := exampleFor(scenario, 5); err == nil {
		t.Fatal("expected out-of-range error")
	}
	// Boundary: scenario has 1 example, valid indices are [0]. Index 1
	// (== len) must be rejected. mutate4go found that >= -> > let this case
	// slip through and crash.
	if _, err := exampleFor(scenario, 1); err == nil {
		t.Fatal("expected out-of-range error at boundary index == len")
	}
	noEx := Scenario{Name: "n"}
	if _, err := exampleFor(noEx, 1); err == nil {
		t.Fatal("expected error for non-zero index on examples-less scenario")
	}
	if _, err := exampleFor(noEx, 0); err != nil {
		t.Fatalf("expected empty example: %v", err)
	}
}
