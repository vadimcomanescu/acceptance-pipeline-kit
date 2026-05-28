package apskit

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestMetadataFilename(t *testing.T) {
	cases := []struct {
		in, want string
	}{
		{"features/Hunt The Wumpus.feature", "features-hunt-the-wumpus-feature.json"},
		{"features/orders/Cancel Order.feature", "features-orders-cancel-order-feature.json"},
		{"Features/API v2/Happy Path.feature", "features-api-v2-happy-path-feature.json"},
	}
	for _, c := range cases {
		if got := MetadataFilename(c.in); got != c.want {
			t.Errorf("MetadataFilename(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

func TestImplementationHashIsDeterministicAndPathSensitive(t *testing.T) {
	dir := t.TempDir()
	a := filepath.Join(dir, "a.txt")
	b := filepath.Join(dir, "b.txt")
	_ = os.WriteFile(a, []byte("alpha"), 0o644)
	_ = os.WriteFile(b, []byte("beta"), 0o644)
	h1, err := ImplementationHash([]string{a, b})
	if err != nil {
		t.Fatal(err)
	}
	h2, err := ImplementationHash([]string{b, a}) // sorted internally
	if err != nil {
		t.Fatal(err)
	}
	if h1 != h2 {
		t.Fatalf("hash not stable under reorder: %q vs %q", h1, h2)
	}
	if !strings.HasPrefix(h1, "sha256:") {
		t.Errorf("hash should start with sha256:, got %q", h1)
	}
	_ = os.WriteFile(b, []byte("gamma"), 0o644)
	h3, _ := ImplementationHash([]string{a, b})
	if h3 == h1 {
		t.Errorf("hash should change when content changes")
	}
}

func TestImplementationHashMissingFile(t *testing.T) {
	if _, err := ImplementationHash([]string{filepath.Join(t.TempDir(), "missing")}); err == nil {
		t.Fatal("expected error for missing file")
	}
}

func TestWriteMetadataEmitsExpectedShape(t *testing.T) {
	dir := t.TempDir()
	gen := filepath.Join(dir, "gen.go")
	_ = os.WriteFile(gen, []byte("// generated\n"), 0o644)
	out, err := WriteMetadata(MetadataInput{
		MetadataDir:    filepath.Join(dir, "metadata"),
		FeaturePath:    "features/orders.feature",
		IRPath:         "build/acceptance/orders.json",
		GeneratedFiles: []string{gen},
	})
	if err != nil {
		t.Fatal(err)
	}
	if filepath.Base(out) != "features-orders-feature.json" {
		t.Errorf("unexpected metadata filename: %q", out)
	}
	raw, _ := os.ReadFile(out)
	var payload map[string]any
	_ = json.Unmarshal(raw, &payload)
	if payload["schema_version"].(float64) != float64(SchemaVersion) {
		t.Errorf("schema_version mismatch")
	}
	if payload["hash_scope"] != "generated_files" {
		t.Errorf("hash_scope mismatch")
	}
	if !strings.HasPrefix(payload["implementation_hash"].(string), "sha256:") {
		t.Errorf("hash format")
	}
}
