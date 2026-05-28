package apskit

import (
	"errors"
	"testing"
)

func TestRegistryStepAndResolve(t *testing.T) {
	r := NewRegistry()
	called := false
	r.Step("ready", func(world World, _ Example) error {
		called = true
		return nil
	})
	fn, err := r.Resolve("ready")
	if err != nil {
		t.Fatalf("resolve: %v", err)
	}
	if err := fn(World{}, Example{}); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if !called {
		t.Fatal("handler was not called")
	}
}

func TestRegistryResolveUnknown(t *testing.T) {
	r := NewRegistry()
	_, err := r.Resolve("never seen")
	var uerr *UnsupportedStepError
	if !errors.As(err, &uerr) {
		t.Fatalf("expected UnsupportedStepError, got %v", err)
	}
	if uerr.Text != "never seen" {
		t.Errorf("unexpected text %q", uerr.Text)
	}
	if got := uerr.Error(); got == "" {
		t.Error("error message should not be empty")
	}
}

func TestRegistryDuplicateStepPanics(t *testing.T) {
	r := NewRegistry()
	r.Step("x", func(World, Example) error { return nil })
	defer func() {
		if recover() == nil {
			t.Fatal("expected panic on duplicate")
		}
	}()
	r.Step("x", func(World, Example) error { return nil })
}

func TestRegistryHas(t *testing.T) {
	r := NewRegistry()
	if r.Has("a") {
		t.Fatal("empty registry should not contain a")
	}
	r.Step("a", func(World, Example) error { return nil })
	if !r.Has("a") {
		t.Fatal("expected to find a")
	}
}
