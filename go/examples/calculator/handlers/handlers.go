// Package handlers registers calculator step handlers with apskit.DefaultRegistry
// from its init function. Importing this package for its side effects (using
// the blank identifier) is what wires up the acceptance pipeline.
package handlers

import (
	"fmt"
	"strconv"

	"github.com/vadimcomanescu/acceptance-pipeline-kit/go/apskit"
)

type calculator struct {
	value int
}

func (c *calculator) add(a, b int)      { c.value = a + b }
func (c *calculator) subtract(a, b int) { c.value = a - b }

func init() {
	r := apskit.DefaultRegistry
	r.Step("a fresh calculator", func(world apskit.World, _ apskit.Example) error {
		world["calc"] = &calculator{}
		return nil
	})
	r.Step("I add <a> and <b>", func(world apskit.World, ex apskit.Example) error {
		a, err := strconv.Atoi(ex["a"])
		if err != nil {
			return err
		}
		b, err := strconv.Atoi(ex["b"])
		if err != nil {
			return err
		}
		world["calc"].(*calculator).add(a, b)
		return nil
	})
	r.Step("I subtract <b> from <a>", func(world apskit.World, ex apskit.Example) error {
		a, err := strconv.Atoi(ex["a"])
		if err != nil {
			return err
		}
		b, err := strconv.Atoi(ex["b"])
		if err != nil {
			return err
		}
		world["calc"].(*calculator).subtract(a, b)
		return nil
	})
	r.Step("the result is <sum>", func(world apskit.World, ex apskit.Example) error {
		want, err := strconv.Atoi(ex["sum"])
		if err != nil {
			return err
		}
		if got := world["calc"].(*calculator).value; got != want {
			return fmt.Errorf("expected %d, got %d", want, got)
		}
		return nil
	})
	r.Step("the result is <diff>", func(world apskit.World, ex apskit.Example) error {
		want, err := strconv.Atoi(ex["diff"])
		if err != nil {
			return err
		}
		if got := world["calc"].(*calculator).value; got != want {
			return fmt.Errorf("expected %d, got %d", want, got)
		}
		return nil
	})
}
