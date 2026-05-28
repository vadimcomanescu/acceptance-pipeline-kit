package apskit

import "fmt"

// World is a per-execution mutable map passed to every step handler.
type World map[string]any

// Example is the current row of example values.
type Example map[string]string

// StepHandler is a function that implements one step.
type StepHandler func(world World, example Example) error

// UnsupportedStepError is returned when no handler is registered for a step.
type UnsupportedStepError struct {
	Text string
}

func (e *UnsupportedStepError) Error() string {
	return fmt.Sprintf("unsupported step: %s", e.Text)
}

// Registry maps step text to handler functions. Exact-text matching is the
// portable baseline; projects may add expression matching on top.
type Registry struct {
	steps map[string]StepHandler
}

// NewRegistry returns a fresh registry.
func NewRegistry() *Registry {
	return &Registry{steps: make(map[string]StepHandler)}
}

// Step registers a handler for the exact step text. Duplicates panic so
// registration errors are caught at process start, not test run time.
func (r *Registry) Step(text string, fn StepHandler) {
	if _, ok := r.steps[text]; ok {
		panic(fmt.Sprintf("duplicate step handler: %q", text))
	}
	r.steps[text] = fn
}

// Resolve returns the handler for text or an *UnsupportedStepError.
func (r *Registry) Resolve(text string) (StepHandler, error) {
	if fn, ok := r.steps[text]; ok {
		return fn, nil
	}
	return nil, &UnsupportedStepError{Text: text}
}

// Has reports whether a handler is registered for text.
func (r *Registry) Has(text string) bool {
	_, ok := r.steps[text]
	return ok
}

// DefaultRegistry is the process-wide registry used by RunExecution when the
// caller does not pass one explicitly. Project handler packages register
// against it from init().
var DefaultRegistry = NewRegistry()
