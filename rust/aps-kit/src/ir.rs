use std::fs;
use std::path::Path;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct Step {
    pub keyword: String,
    pub text: String,
    #[serde(default)]
    pub parameters: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Scenario {
    pub name: String,
    pub steps: Vec<Step>,
    #[serde(default)]
    pub examples: Vec<std::collections::BTreeMap<String, String>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Feature {
    pub name: String,
    #[serde(default)]
    pub background: Vec<Step>,
    #[serde(default)]
    pub scenarios: Vec<Scenario>,
}

pub fn load_ir<P: AsRef<Path>>(path: P) -> Result<Feature, String> {
    let bytes = fs::read(path.as_ref()).map_err(|e| format!("read IR {:?}: {e}", path.as_ref()))?;
    let feature: Feature =
        serde_json::from_slice(&bytes).map_err(|e| format!("decode IR: {e}"))?;
    if feature.name.is_empty() {
        return Err("feature IR missing 'name'".into());
    }
    Ok(feature)
}
