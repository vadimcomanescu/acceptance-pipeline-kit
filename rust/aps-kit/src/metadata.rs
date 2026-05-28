use std::fs;
use std::path::{Path, PathBuf};

use sha2::{Digest, Sha256};

pub const SCHEMA_VERSION: u32 = 1;

pub fn metadata_filename(feature_path: &str) -> String {
    let lower = feature_path.to_lowercase();
    let mut out = String::with_capacity(lower.len());
    let mut last_dash = true; // strip leading dashes
    for ch in lower.chars() {
        if ch.is_ascii_alphanumeric() {
            out.push(ch);
            last_dash = false;
        } else if !last_dash {
            out.push('-');
            last_dash = true;
        }
    }
    while out.ends_with('-') {
        out.pop();
    }
    out.push_str(".json");
    out
}

pub fn implementation_hash(generated_files: &[PathBuf]) -> Result<String, String> {
    let mut sorted: Vec<&PathBuf> = generated_files.iter().collect();
    sorted.sort();
    let mut hasher = Sha256::new();
    for path in sorted {
        let path_str = path.to_string_lossy();
        hasher.update(path_str.as_bytes());
        hasher.update([0u8]);
        let bytes = fs::read(path).map_err(|e| format!("hash {path:?}: {e}"))?;
        hasher.update(&bytes);
        hasher.update([0u8]);
    }
    Ok(format!("sha256:{:x}", hasher.finalize()))
}

pub struct MetadataInput<'a> {
    pub metadata_dir: &'a Path,
    pub feature_path: &'a str,
    pub ir_path: &'a str,
    pub generated_files: &'a [PathBuf],
}

pub fn write_metadata(input: MetadataInput<'_>) -> Result<PathBuf, String> {
    fs::create_dir_all(input.metadata_dir).map_err(|e| e.to_string())?;
    let hash = implementation_hash(input.generated_files)?;
    let payload = serde_json::json!({
        "schema_version": SCHEMA_VERSION,
        "feature_path": input.feature_path,
        "ir_path": input.ir_path,
        "implementation_hash": hash,
        "hash_scope": "generated_files",
        "generated_files": input.generated_files.iter().map(|p| p.to_string_lossy().to_string()).collect::<Vec<_>>(),
    });
    let out = input.metadata_dir.join(metadata_filename(input.feature_path));
    let serialized = serde_json::to_string_pretty(&payload).map_err(|e| e.to_string())?;
    fs::write(&out, format!("{serialized}\n")).map_err(|e| e.to_string())?;
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalizes_filenames() {
        assert_eq!(
            metadata_filename("features/Hunt The Wumpus.feature"),
            "features-hunt-the-wumpus-feature.json"
        );
        assert_eq!(
            metadata_filename("features/orders/Cancel Order.feature"),
            "features-orders-cancel-order-feature.json"
        );
        assert_eq!(
            metadata_filename("Features/API v2/Happy Path.feature"),
            "features-api-v2-happy-path-feature.json"
        );
    }
}
