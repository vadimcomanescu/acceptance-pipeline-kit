use std::fs;
use std::path::PathBuf;

use aps_kit::metadata::{implementation_hash, metadata_filename, write_metadata, MetadataInput, SCHEMA_VERSION};

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

#[test]
fn implementation_hash_is_stable_and_path_sensitive() {
    let tmp = tempdir();
    let a = tmp.path().join("a.txt");
    let b = tmp.path().join("b.txt");
    fs::write(&a, "alpha").unwrap();
    fs::write(&b, "beta").unwrap();
    let files = vec![a.clone(), b.clone()];
    let h1 = implementation_hash(&files).unwrap();
    let reordered = vec![b.clone(), a.clone()];
    let h2 = implementation_hash(&reordered).unwrap();
    assert_eq!(h1, h2);
    assert!(h1.starts_with("sha256:"));
    fs::write(&b, "gamma").unwrap();
    let h3 = implementation_hash(&files).unwrap();
    assert_ne!(h1, h3);
}

#[test]
fn implementation_hash_propagates_io_error() {
    let tmp = tempdir();
    let missing = tmp.path().join("missing");
    let err = implementation_hash(&[missing]).unwrap_err();
    assert!(err.contains("hash"));
}

#[test]
fn write_metadata_emits_expected_shape() {
    let tmp = tempdir();
    let generated = tmp.path().join("gen.rs");
    fs::write(&generated, "// generated").unwrap();
    let metadata_dir = tmp.path().join("metadata");
    let generated_files: Vec<PathBuf> = vec![generated.clone()];
    let out = write_metadata(MetadataInput {
        metadata_dir: &metadata_dir,
        feature_path: "features/orders.feature",
        ir_path: "build/acceptance/orders.json",
        generated_files: &generated_files,
    })
    .unwrap();
    assert!(out.ends_with("features-orders-feature.json"));
    let payload: serde_json::Value =
        serde_json::from_str(&fs::read_to_string(&out).unwrap()).unwrap();
    assert_eq!(payload["schema_version"], SCHEMA_VERSION);
    assert_eq!(payload["hash_scope"], "generated_files");
    assert!(payload["implementation_hash"]
        .as_str()
        .unwrap()
        .starts_with("sha256:"));
    assert_eq!(payload["feature_path"], "features/orders.feature");
}

struct TempDir(std::path::PathBuf);
impl TempDir {
    fn path(&self) -> &std::path::Path { &self.0 }
}
impl Drop for TempDir {
    fn drop(&mut self) { let _ = std::fs::remove_dir_all(&self.0); }
}
fn tempdir() -> TempDir {
    let mut p = std::env::temp_dir();
    p.push(format!(
        "aps-kit-test-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    std::fs::create_dir_all(&p).unwrap();
    TempDir(p)
}
