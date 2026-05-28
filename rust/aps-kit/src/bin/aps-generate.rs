use std::path::Path;
use std::process::ExitCode;

use aps_kit::generator::{generate, GenerateOptions};

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut positional: Vec<String> = Vec::new();
    let mut feature_path: Option<String> = None;
    let mut handlers_crate: String = "handlers".into();
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--feature-path" => {
                i += 1;
                if i >= args.len() {
                    return usage();
                }
                feature_path = Some(args[i].clone());
            }
            "--handlers-crate" => {
                i += 1;
                if i >= args.len() {
                    return usage();
                }
                handlers_crate = args[i].clone();
            }
            "--help" | "-h" => {
                eprintln!("usage: aps-generate [--feature-path PATH] [--handlers-crate NAME] <json-ir> <output-dir>");
                return ExitCode::SUCCESS;
            }
            other if other.starts_with("--") => return usage(),
            _ => positional.push(args[i].clone()),
        }
        i += 1;
    }
    if positional.len() != 2 {
        return usage();
    }
    let opts = GenerateOptions {
        ir_path: Path::new(&positional[0]),
        output_dir: Path::new(&positional[1]),
        feature_path: feature_path.as_deref(),
        handlers_crate: &handlers_crate,
    };
    match generate(opts) {
        Ok(_) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("aps-generate: {e}");
            ExitCode::from(1)
        }
    }
}

fn usage() -> ExitCode {
    eprintln!("usage: aps-generate [--feature-path PATH] [--handlers-crate NAME] <json-ir> <output-dir>");
    ExitCode::from(2)
}
