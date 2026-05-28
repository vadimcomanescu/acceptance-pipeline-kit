use aps_kit::registry::{Registry, StepError};

#[test]
fn step_registers_handler() {
    let reg = Registry::new();
    reg.step("ready", |world, _ex| {
        world
            .as_object_mut()
            .unwrap()
            .insert("seen".into(), serde_json::json!(true));
        Ok(())
    });
    assert!(reg.has("ready"));
    let mut world = serde_json::json!({});
    let example = Default::default();
    reg.invoke("ready", &mut world, &example).unwrap();
    assert_eq!(world["seen"], serde_json::json!(true));
}

#[test]
fn invoke_unknown_step_returns_unsupported() {
    let reg = Registry::new();
    let mut world = serde_json::json!({});
    let example = Default::default();
    match reg.invoke("never", &mut world, &example) {
        Err(StepError::Unsupported(text)) => assert_eq!(text, "never"),
        other => panic!("expected Unsupported, got {other:?}"),
    }
}

#[test]
fn step_error_display_renders_each_variant() {
    let u = StepError::Unsupported("x".into());
    let m = StepError::MissingParameter { step: "s".into(), param: "p".into() };
    let f = StepError::Failure("boom".into());
    assert!(format!("{u}").contains("unsupported"));
    assert!(format!("{m}").contains("missing"));
    assert!(format!("{f}").contains("boom"));
}

#[test]
#[should_panic(expected = "duplicate step handler")]
fn duplicate_step_panics() {
    let reg = Registry::new();
    reg.step("x", |_w, _ex| Ok(()));
    reg.step("x", |_w, _ex| Ok(()));
}

#[test]
fn registry_default_constructs() {
    let _r: Registry = Default::default();
}
