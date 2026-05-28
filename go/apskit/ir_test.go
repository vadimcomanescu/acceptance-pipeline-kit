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

func assertLoadIRError(t *testing.T, contents []byte, want string) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "ir.json")
	if err := os.WriteFile(path, contents, 0o644); err != nil {
		t.Fatal(err)
	}
	_, err := LoadIR(path)
	if err == nil || !strings.Contains(err.Error(), want) {
		t.Fatalf("expected %q, got %v", want, err)
	}
}

func TestLoadIRInvalidJSON(t *testing.T) {
	assertLoadIRError(t, []byte("not json"), "decode IR")
}

func TestLoadIRRejectsMissingName(t *testing.T) {
	assertLoadIRError(t, []byte(`{"scenarios":[]}`), "missing 'name'")
}
