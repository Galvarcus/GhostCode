//! The binary: arguments in, report out, exit status.
//!
//! License: GNU GPL 3.0

use std::process::ExitCode;

use clap::Parser;

use ghostcode::cli::Args;
use ghostcode::config::Config;

fn main() -> ExitCode {
    if let Err(e) = run() {
        eprintln!("{}: {e}", ghostcode::NAME);
        return ExitCode::from(2);
    }
    ExitCode::SUCCESS
}

/// FUNCTION: One run, from arguments to report. Every failure returns
/// here, so that the program has one place that prints an error.
fn run() -> anyhow::Result<()> {
    let args = Args::parse();
    let root = args.root_dir()?;
    let _cfg = Config::load(&root, &args)?;
    Ok(())
}
