use std::path::Path;

use crate::ir::{load_ir, Feature, Scenario, Step};
use crate::registry::{default_registry, Example, Registry, StepError, World};

/// Yields (scenarioIndex, exampleIndex) pairs the runtime must execute.
pub fn executions_for(feature: &Feature) -> Vec<(usize, usize)> {
    let mut out = Vec::new();
    for (s_idx, scenario) in feature.scenarios.iter().enumerate() {
        if scenario.examples.is_empty() {
            out.push((s_idx, 0));
        } else {
            for e_idx in 0..scenario.examples.len() {
                out.push((s_idx, e_idx));
            }
        }
    }
    out
}

fn example_for(scenario: &Scenario, example_index: usize) -> Result<Example, StepError> {
    if scenario.examples.is_empty() {
        if example_index != 0 {
            return Err(StepError::Failure(format!(
                "scenario {:?} has no examples; only exampleIndex=0 is valid",
                scenario.name
            )));
        }
        return Ok(Example::new());
    }
    let row = scenario
        .examples
        .get(example_index)
        .ok_or_else(|| StepError::Failure(format!(
            "example index {} out of range for scenario {:?}",
            example_index, scenario.name
        )))?;
    Ok(row.clone())
}

fn run_step(
    step: &Step,
    world: &mut World,
    example: &Example,
    registry: &Registry,
) -> Result<(), StepError> {
    for param in &step.parameters {
        if !example.contains_key(param) {
            return Err(StepError::MissingParameter {
                step: step.text.clone(),
                param: param.clone(),
            });
        }
    }
    registry.invoke(&step.text, world, example)
}

/// Runs one (scenario, example) execution from the IR file at `ir_path`.
/// Uses `default_registry()` when `registry` is `None`.
pub fn run_execution<P: AsRef<Path>>(
    ir_path: P,
    scenario_index: usize,
    example_index: usize,
    registry: Option<&Registry>,
) -> Result<(), StepError> {
    let feature = load_ir(&ir_path).map_err(StepError::Failure)?;
    let scenario = feature
        .scenarios
        .get(scenario_index)
        .ok_or_else(|| StepError::Failure(format!(
            "scenario index {scenario_index} out of range; feature has {} scenarios",
            feature.scenarios.len()
        )))?;
    let example = example_for(scenario, example_index)?;
    let reg = registry.unwrap_or_else(|| default_registry());
    let mut world: World = serde_json::json!({});
    for step in &feature.background {
        run_step(step, &mut world, &example, reg)?;
    }
    for step in &scenario.steps {
        run_step(step, &mut world, &example, reg)?;
    }
    Ok(())
}
