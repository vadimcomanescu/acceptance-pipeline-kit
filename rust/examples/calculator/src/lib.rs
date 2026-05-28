//! Step handlers for the calculator example.
//!
//! The generated test calls `register()` once before running any scenario,
//! which populates `aps_kit::default_registry()` with the handlers below.

use std::sync::Once;

use aps_kit::registry::{default_registry, Example, StepError, World};

static REGISTERED: Once = Once::new();

fn calc(world: &mut World) -> &mut serde_json::Map<String, serde_json::Value> {
    world
        .as_object_mut()
        .expect("world is a JSON object")
}

fn read_int(value: &serde_json::Value) -> i64 {
    if let Some(n) = value.as_i64() {
        return n;
    }
    value
        .as_str()
        .and_then(|s| s.parse::<i64>().ok())
        .unwrap_or(0)
}

pub fn register() {
    REGISTERED.call_once(|| {
        let reg = default_registry();
        reg.step("a fresh calculator", |world, _ex| {
            let obj = calc(world);
            obj.insert("value".into(), serde_json::json!(0));
            Ok(())
        });
        reg.step("I add <a> and <b>", |world, ex| {
            let a: i64 = ex["a"].parse().map_err(|e| StepError::Failure(format!("{e}")))?;
            let b: i64 = ex["b"].parse().map_err(|e| StepError::Failure(format!("{e}")))?;
            calc(world).insert("value".into(), serde_json::json!(a + b));
            Ok(())
        });
        reg.step("I subtract <b> from <a>", |world, ex: &Example| {
            let a: i64 = ex["a"].parse().map_err(|e| StepError::Failure(format!("{e}")))?;
            let b: i64 = ex["b"].parse().map_err(|e| StepError::Failure(format!("{e}")))?;
            calc(world).insert("value".into(), serde_json::json!(a - b));
            Ok(())
        });
        reg.step("the result is <sum>", |world, ex: &Example| {
            let want: i64 = ex["sum"].parse().map_err(|e| StepError::Failure(format!("{e}")))?;
            let got = read_int(calc(world).get("value").unwrap_or(&serde_json::Value::Null));
            if got != want {
                return Err(StepError::Failure(format!("expected {want}, got {got}")));
            }
            Ok(())
        });
        reg.step("the result is <diff>", |world, ex: &Example| {
            let want: i64 = ex["diff"].parse().map_err(|e| StepError::Failure(format!("{e}")))?;
            let got = read_int(calc(world).get("value").unwrap_or(&serde_json::Value::Null));
            if got != want {
                return Err(StepError::Failure(format!("expected {want}, got {got}")));
            }
            Ok(())
        });
    });
}

