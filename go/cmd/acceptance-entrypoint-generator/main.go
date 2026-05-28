// acceptance-entrypoint-generator is the APS-conformant entrypoint generator
// for Go projects.
//
// Usage:
//
//	acceptance-entrypoint-generator <json-ir> <generated-test-output>
//
// Two positional arguments, nothing else. Configuration via env vars:
//
//	APS_FEATURE_PATH   feature path to record in metadata (default: <json-ir>)
//	APS_PACKAGE        Go package name for the generated test file (default: generated)
package main

import (
	"fmt"
	"os"

	"github.com/vadimcomanescu/acceptance-pipeline-kit/go/apskit"
)

const usage = "usage: acceptance-entrypoint-generator <json-ir> <generated-test-output>"

func main() {
	args := os.Args[1:]
	if len(args) > 0 && (args[0] == "-h" || args[0] == "--help") {
		fmt.Fprintln(os.Stderr, usage)
		return
	}
	if len(args) != 2 {
		fmt.Fprintln(os.Stderr, usage)
		os.Exit(2)
	}
	_, err := apskit.Generate(apskit.GenerateOptions{
		IRPath:      args[0],
		OutputDir:   args[1],
		FeaturePath: os.Getenv("APS_FEATURE_PATH"),
		PackageName: os.Getenv("APS_PACKAGE"),
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "acceptance-entrypoint-generator: %v\n", err)
		os.Exit(1)
	}
}
