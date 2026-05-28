//! Project-specific Acceptance Pipeline components in Rust:
//! JSON IR types, runtime, step-handler registry, metadata helpers,
//! entrypoint generator, and runner adapter.
//!
//! The parser and mutator remain the upstream Go binaries from
//! `github.com/unclebob/Acceptance-Pipeline-Specification`.

pub mod adapter;
pub mod cli;
pub mod generator;
pub mod ir;
pub mod metadata;
pub mod registry;
pub mod runtime;

pub use ir::{load_ir, Feature, Scenario, Step};
pub use registry::{default_registry, Registry, StepError, StepHandler, World};
pub use runtime::{executions_for, run_execution};
