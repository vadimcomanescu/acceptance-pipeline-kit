package apskit

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

// SchemaVersion is the generator metadata schema version.
const SchemaVersion = 1

var nonAlnum = regexp.MustCompile(`[^a-z0-9]+`)

// MetadataFilename normalizes a feature path to the spec-defined metadata
// filename, e.g. features/Hunt The Wumpus.feature ->
// features-hunt-the-wumpus-feature.json.
func MetadataFilename(featurePath string) string {
	lower := strings.ToLower(featurePath)
	hyphen := nonAlnum.ReplaceAllString(lower, "-")
	hyphen = strings.Trim(hyphen, "-")
	return hyphen + ".json"
}

// ImplementationHash returns sha256:<hex> over the generated files only.
func ImplementationHash(generatedFiles []string) (string, error) {
	sorted := append([]string(nil), generatedFiles...)
	sort.Strings(sorted)
	h := sha256.New()
	for _, f := range sorted {
		h.Write([]byte(f))
		h.Write([]byte{0})
		data, err := os.ReadFile(f)
		if err != nil {
			return "", fmt.Errorf("hash %s: %w", f, err)
		}
		h.Write(data)
		h.Write([]byte{0})
	}
	return "sha256:" + hex.EncodeToString(h.Sum(nil)), nil
}

// MetadataInput is the input for WriteMetadata.
type MetadataInput struct {
	MetadataDir    string
	FeaturePath    string
	IRPath         string
	GeneratedFiles []string
}

// WriteMetadata writes <MetadataDir>/<feature-metadata-name>.json describing
// the generated tests for one feature.
func WriteMetadata(in MetadataInput) (string, error) {
	if err := os.MkdirAll(in.MetadataDir, 0o755); err != nil {
		return "", err
	}
	hash, err := ImplementationHash(in.GeneratedFiles)
	if err != nil {
		return "", err
	}
	payload := map[string]any{
		"schema_version":      SchemaVersion,
		"feature_path":        in.FeaturePath,
		"ir_path":             in.IRPath,
		"implementation_hash": hash,
		"hash_scope":          "generated_files",
		"generated_files":     in.GeneratedFiles,
	}
	out := filepath.Join(in.MetadataDir, MetadataFilename(in.FeaturePath))
	data, err := json.MarshalIndent(payload, "", "  ")
	if err != nil {
		return "", err
	}
	data = append(data, '\n')
	if err := os.WriteFile(out, data, 0o644); err != nil {
		return "", err
	}
	return out, nil
}
