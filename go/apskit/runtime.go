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

// mutate4go-manifest-begin
// {"version":1,"tested_at":"2026-05-28T18:13:19+02:00","module_hash":"30b27784c1ee5bb2979587fe5a44230e84c8a9027599e82eae31b6b9deee65ff","functions":[{"id":"func/ExecutionsFor","name":"ExecutionsFor","line":7,"end_line":19,"hash":"178caac53ad5bdd9ed1fdaf04902d851c9824a10199a8af4d5918886bb9344b5"},{"id":"func/exampleFor","name":"exampleFor","line":21,"end_line":36,"hash":"1c867c8a7c0c4c8018ce375651be5af66398143f02ff3efe8c8f3b83e2f08a90"},{"id":"func/runStep","name":"runStep","line":38,"end_line":52,"hash":"02dbe1548f4a4b3b8b342e41bfa93ae57149160d3e9d225bc39403c51110ba73"},{"id":"func/RunExecution","name":"RunExecution","line":56,"end_line":84,"hash":"fe85fac20cffa7cc12e50b44a731e22af2e7d50ce129e6506ee926600042aba4"}]}
// mutate4go-manifest-end
