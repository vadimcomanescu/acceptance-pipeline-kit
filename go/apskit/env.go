package apskit

import "os"

func envOrCurrent() []string {
	return append([]string(nil), os.Environ()...)
}
