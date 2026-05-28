package apskit

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestLoadIRMissingFile(t *testing.T) {
	_, err := LoadIR(filepath.Join(t.TempDir(), "missing.json"))
	if err == nil || !strings.Contains(err.Error(), "read IR") {
		t.Fatalf("expected read error, got %v", err)
	}
}

func TestLoadIRInvalidJSON(t *testing.T) {
	path := filepath.Join(t.TempDir(), "bad.json")
	if err := os.WriteFile(path, []byte("not json"), 0o644); err != nil {
		t.Fatal(err)
	}
	_, err := LoadIR(path)
	if err == nil || !strings.Contains(err.Error(), "decode IR") {
		t.Fatalf("expected decode error, got %v", err)
	}
}

func TestLoadIRRejectsMissingName(t *testing.T) {
	path := filepath.Join(t.TempDir(), "noname.json")
	if err := os.WriteFile(path, []byte(`{"scenarios":[]}`), 0o644); err != nil {
		t.Fatal(err)
	}
	_, err := LoadIR(path)
	if err == nil || !strings.Contains(err.Error(), "missing 'name'") {
		t.Fatalf("expected missing name error, got %v", err)
	}
}
