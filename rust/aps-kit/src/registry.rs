use std::collections::{BTreeMap, HashMap};
use std::sync::Mutex;

use once_cell::sync::Lazy;

/// World is an opaque per-execution scratchpad. We model it with serde_json::Value
/// because handlers in different projects need different types and Rust does not
/// have an Any-friendly map shape that round-trips ergonomically.
pub type World = serde_json::Value;
pub type Example = BTreeMap<String, String>;

#[derive(Debug)]
pub enum StepError {
    Unsupported(String),
    MissingParameter { step: String, param: String },
    Failure(String),
}

impl std::fmt::Display for StepError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            StepError::Unsupported(s) => write!(f, "unsupported step: {s}"),
            StepError::MissingParameter { step, param } => write!(
                f,
                "step {step:?} references missing example value {param:?}"
            ),
            StepError::Failure(s) => f.write_str(s),
        }
    }
}

impl std::error::Error for StepError {}

pub type StepHandler =
    Box<dyn Fn(&mut World, &Example) -> Result<(), StepError> + Send + Sync + 'static>;

pub struct Registry {
    steps: Mutex<HashMap<String, StepHandler>>,
}

impl Registry {
    pub fn new() -> Self {
        Self {
            steps: Mutex::new(HashMap::new()),
        }
    }

    pub fn step<F>(&self, text: impl Into<String>, fn_: F)
    where
        F: Fn(&mut World, &Example) -> Result<(), StepError> + Send + Sync + 'static,
    {
        let text = text.into();
        let mut guard = self.steps.lock().unwrap();
        if guard.contains_key(&text) {
            panic!("duplicate step handler: {text:?}");
        }
        guard.insert(text, Box::new(fn_));
    }

    pub fn invoke(
        &self,
        text: &str,
        world: &mut World,
        example: &Example,
    ) -> Result<(), StepError> {
        let guard = self.steps.lock().unwrap();
        let handler = guard
            .get(text)
            .ok_or_else(|| StepError::Unsupported(text.to_string()))?;
        handler(world, example)
    }

    pub fn has(&self, text: &str) -> bool {
        self.steps.lock().unwrap().contains_key(text)
    }
}

impl Default for Registry {
    fn default() -> Self {
        Self::new()
    }
}

/// Process-wide registry. Project handlers register against it from a
/// project-specific `register()` function the generated test file calls.
pub fn default_registry() -> &'static Registry {
    static DEFAULT: Lazy<Registry> = Lazy::new(Registry::new);
    &DEFAULT
}
