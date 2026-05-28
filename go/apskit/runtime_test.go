package apskit

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strconv"
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
