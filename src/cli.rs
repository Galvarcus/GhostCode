//! The command line: what one run was asked to do.
//!
//! License: GNU GPL 3.0

use std::path::PathBuf;

use anyhow::bail;
use clap::Parser;
use clap::ValueEnum;

/// How a report is printed. JSON is the contract that a front end
/// reads; text is for a person at a terminal, and for the quickfix
/// line that Vim's own workflow writes.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, ValueEnum)]
pub enum Format {
    #[default]
    Json,
    Text,
}

/// The finding classes a run may turn on. None is "the user said
/// nothing", which is not the same as false: a setting in
/// ghostcode.toml must survive a run that does not mention it.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, clap::Args)]
pub struct FindingArgs {
    // Hidden because nothing emits the class, and a flag that names
    // a detection the binary cannot give is worse than no flag. The
    // setting is still read and carried, so that ghostcode.toml keeps
    // its shape.
    // REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
    #[arg(long = "write-only", hide = true)]
    pub write_only: Option<bool>,

    /// Whether to report a variable of a function body that nothing
    /// reads.
    #[arg(long = "locals")]
    pub locals: Option<bool>,

    /// Whether to report a variable in g: that the project writes
    /// and nothing reads.
    #[arg(long = "globals")]
    pub globals: Option<bool>,

    /// Whether to report a variable in b: that the project writes
    /// and nothing reads.
    #[arg(long = "buffer-vars")]
    pub buffer_vars: Option<bool>,

    /// Whether to report a variable in w: that the project writes
    /// and nothing reads.
    #[arg(long = "window-vars")]
    pub window_vars: Option<bool>,

    /// Whether to report a variable in t: that the project writes
    /// and nothing reads.
    #[arg(long = "tab-vars")]
    pub tab_vars: Option<bool>,
}

#[derive(Debug, Clone, Parser)]
#[command(name = crate::NAME, version, about = "Find unreferenced code in a project.")]
pub struct Args {
    /// The project to scan. Defaults to the working directory.
    #[arg(default_value = ".")]
    pub root: PathBuf,

    /// The output format.
    #[arg(long, value_enum, default_value_t = Format::Json)]
    pub format: Format,

    /// Whether an exported symbol counts as public API and is never
    /// reported.
    #[arg(long = "exports-are-api")]
    pub exports_are_api: Option<bool>,

    /// Read every file, including the ones git ignores.
    #[arg(long = "no-ignore")]
    pub no_ignore: bool,

    #[command(flatten)]
    pub findings: FindingArgs,

    // Hidden because it serves a survey of the analyzer, not a user:
    // what it lists measures the analyzer, and no finding comes of it.
    // REFERENCE: https://github.com/Galvarcus/GhostCode/issues/84
    #[arg(long = "unplaced", hide = true)]
    pub unplaced: bool,
}

impl Args {
    /// METHOD: Parse an argument vector. The tests reach the parser
    /// through this, so that they need no dependency on clap.
    ///
    /// # Errors
    /// When an argument is unknown or a value will not parse.
    pub fn from_argv(argv: &[&str]) -> anyhow::Result<Self> {
        Ok(Self::try_parse_from(argv)?)
    }

    /// METHOD: The root, proved to be a directory that exists, so that
    /// every later stage can trust it.
    ///
    /// # Errors
    /// When the root is missing, is not a directory, or cannot be
    /// resolved to an absolute path.
    pub fn root_dir(&self) -> anyhow::Result<PathBuf> {
        if !self.root.exists() {
            bail!("{}: no such directory", self.root.display());
        }
        if !self.root.is_dir() {
            bail!("{}: not a directory", self.root.display());
        }
        Ok(self.root.canonicalize()?)
    }
}
