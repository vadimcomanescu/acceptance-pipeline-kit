// aps-adapter is a persistent NDJSON worker that gherkin-mutator launches via
// --runner-worker. Usage:
//
//	aps-adapter <test-cmd> [test-args...]
//
// Everything after the program name is the project's test command. The
// adapter sets APS_IR_PATH for each mutator job. This positional form
// survives gherkin-mutator's strings.Fields splitting of --runner-worker.
package main

import (
	"fmt"
	"os"

	"github.com/vadimcomanescu/acceptance-pipeline-kit/go/apskit"
)

func main() {
	args := os.Args[1:]
	if len(args) == 0 || args[0] == "-h" || args[0] == "--help" {
		fmt.Fprintln(os.Stderr, "usage: aps-adapter <test-cmd> [test-args...]")
		if len(args) == 0 {
			os.Exit(2)
		}
		return
	}
	err := apskit.Serve(apskit.AdapterOptions{
		Command: args,
		Stdin:   os.Stdin,
		Stdout:  os.Stdout,
		Stderr:  os.Stderr,
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "aps-adapter: %v\n", err)
		os.Exit(1)
	}
}
