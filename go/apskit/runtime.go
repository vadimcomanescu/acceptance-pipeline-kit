package apskit

import "fmt"

// ExecutionsFor returns the (scenarioIndex, exampleIndex) pairs the runtime
// must execute. A scenario without examples yields one pair with example 0.
func ExecutionsFor(f *Feature) [][2]int {
	var out [][2]int
	for sIdx, s := range f.Scenarios {
		if len(s.Examples) == 0 {
			out = append(out, [2]int{sIdx, 0})
			continue
		}
		for eIdx := range s.Examples {
			out = append(out, [2]int{sIdx, eIdx})
		}
	}
	return out
}

func exampleFor(s Scenario, exampleIndex int) (Example, error) {
	if len(s.Examples) == 0 {
		if exampleIndex != 0 {
			return nil, fmt.Errorf("scenario %q has no examples; only exampleIndex=0 is valid", s.Name)
		}
		return Example{}, nil
	}
	if exampleIndex < 0 || exampleIndex >= len(s.Examples) {
		return nil, fmt.Errorf("example index %d out of range for scenario %q", exampleIndex, s.Name)
	}
	out := make(Example, len(s.Examples[exampleIndex]))
	for k, v := range s.Examples[exampleIndex] {
		out[k] = v
	}
	return out, nil
}

func runStep(step Step, world World, example Example, reg *Registry) error {
	// Resolve the handler first so an unsupported step gives the most useful
	// error before we check anything else; then validate required example
	// values; then invoke. Same order in all four language runtimes.
	fn, err := reg.Resolve(step.Text)
	if err != nil {
		return err
	}
	for _, p := range step.Parameters {
		if _, ok := example[p]; !ok {
			return fmt.Errorf("step %q references missing example value %q", step.Text, p)
		}
	}
	return fn(world, example)
}

// RunExecution loads the IR file and runs one scenario/example execution. If
// reg is nil, DefaultRegistry is used.
func RunExecution(irPath string, scenarioIndex, exampleIndex int, reg *Registry) error {
	if reg == nil {
		reg = DefaultRegistry
	}
	feature, err := LoadIR(irPath)
	if err != nil {
		return err
	}
	if scenarioIndex < 0 || scenarioIndex >= len(feature.Scenarios) {
		return fmt.Errorf("scenario index %d out of range; feature has %d scenarios", scenarioIndex, len(feature.Scenarios))
	}
	scenario := feature.Scenarios[scenarioIndex]
	example, err := exampleFor(scenario, exampleIndex)
	if err != nil {
		return err
	}
	world := World{}
	for _, step := range feature.Background {
		if err := runStep(step, world, example, reg); err != nil {
			return err
		}
	}
	for _, step := range scenario.Steps {
		if err := runStep(step, world, example, reg); err != nil {
			return err
		}
	}
	return nil
}
