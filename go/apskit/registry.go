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

// mutate4go-manifest-begin
// {"version":1,"tested_at":"2026-05-28T18:13:38+02:00","module_hash":"47ef8ad038b16ababa43ca74f128b9e520e3fa0d9ef25fa91a8353fcc7315466","functions":[{"id":"func/UnsupportedStepError.Error","name":"UnsupportedStepError.Error","line":19,"end_line":21,"hash":"f7652031d47c44a7d02389c629b326bb1ec606c2516829a61a3c597d35d4da67"},{"id":"func/NewRegistry","name":"NewRegistry","line":30,"end_line":32,"hash":"84a5b251fad03977a3c010615c28c5f93f97f2c699139dd74ab422dc8c67c181"},{"id":"func/Registry.Step","name":"Registry.Step","line":36,"end_line":41,"hash":"044e46280cc32170c1637180b4a26bddb1703b178ebc182a6c976554ad792c32"},{"id":"func/Registry.Resolve","name":"Registry.Resolve","line":44,"end_line":49,"hash":"fde9704f5c0d3a10d96fedd058d0b93d79e849d92717c6d254a48637e4d35597"},{"id":"func/Registry.Has","name":"Registry.Has","line":52,"end_line":55,"hash":"c78b0e853e3bc9f45ce9f7dd5627f11307485d195b37477298f79f40b15c30f3"}]}
// mutate4go-manifest-end
