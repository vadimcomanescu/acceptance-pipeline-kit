// aps-generate is the Acceptance Pipeline entrypoint generator for Go projects.
package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/vadimcomanescu/acceptance-pipeline-kit/go/apskit"
)

func main() {
	featurePath := flag.String("feature-path", "", "Original .feature path recorded in metadata. Defaults to the IR path.")
	pkgName := flag.String("package", "generated", "Go package name for the generated test file.")
	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "usage: aps-generate [flags] <json-ir> <output-dir>\n")
		flag.PrintDefaults()
	}
	flag.Parse()
	if flag.NArg() != 2 {
		flag.Usage()
		os.Exit(2)
	}
	_, err := apskit.Generate(apskit.GenerateOptions{
		IRPath:      flag.Arg(0),
		OutputDir:   flag.Arg(1),
		FeaturePath: *featurePath,
		PackageName: *pkgName,
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "aps-generate: %v\n", err)
		os.Exit(1)
	}
}
