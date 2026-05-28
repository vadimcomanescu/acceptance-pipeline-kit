// Package apskit implements the project-specific Acceptance Pipeline
// components: JSON IR types, runtime, step-handler registry, and metadata
// helpers. The parser and mutator remain the upstream Go binaries from
// github.com/unclebob/Acceptance-Pipeline-Specification.
package apskit

import (
	"encoding/json"
	"fmt"
	"os"
)

// Step is one Gherkin step.
type Step struct {
	Keyword    string   `json:"keyword"`
	Text       string   `json:"text"`
	Parameters []string `json:"parameters,omitempty"`
}

// Scenario is one Gherkin scenario or scenario outline.
type Scenario struct {
	Name     string              `json:"name"`
	Steps    []Step              `json:"steps"`
	Examples []map[string]string `json:"examples"`
}

// Feature is the IR root.
type Feature struct {
	Name       string     `json:"name"`
	Background []Step     `json:"background,omitempty"`
	Scenarios  []Scenario `json:"scenarios"`
}

// LoadIR reads and validates a JSON IR file.
func LoadIR(path string) (*Feature, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read IR: %w", err)
	}
	var f Feature
	if err := json.Unmarshal(data, &f); err != nil {
		return nil, fmt.Errorf("decode IR: %w", err)
	}
	if f.Name == "" {
		return nil, fmt.Errorf("feature IR missing 'name'")
	}
	return &f, nil
}
