//! The settings of one run: the defaults, the file, and the flags.
//!
//! License: GNU GPL 3.0

use std::path::Path;
use std::path::PathBuf;

use anyhow::Context;
use serde::Deserialize;

use crate::cli::Args;

const FILE: &str = "ghostcode.toml";

/// Which classes of finding a run reports. Only `ghost` is always on.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct FindingFlags {
    pub write_only: bool,
    pub locals: bool,

    /// One for each scope whose variables every file shares. A scope
    /// is asked for by itself, because a project may want its settings
    /// checked and not the state it keeps on a buffer.
    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/55
    pub globals: bool,
    pub buffer_vars: bool,
    pub window_vars: bool,
    pub tab_vars: bool,
}

/// What ghostcode.toml holds. Its defaults are the program's defaults,
/// so that a file naming one key leaves the others alone.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(default, deny_unknown_fields)]
struct FileCfg {
    exports_are_api: bool,
    ignore: Vec<String>,
    entry: Vec<PathBuf>,
    external: Vec<String>,
    findings: FindingFlags,
}

impl Default for FileCfg {
    fn default() -> Self {
        Self {
            exports_are_api: true,
            ignore: Vec::new(),
            entry: Vec::new(),
            external: Vec::new(),
            findings: FindingFlags::default(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Config {
    pub exports_are_api: bool,
    pub ignore: Vec<String>,
    pub entry: Vec<PathBuf>,

    /// The variables the project writes for a reader outside it, each
    /// by its full spelling, where `*` stands for any run of
    /// characters: `g:tlinks_*`. One listed here is never reported.
    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/55
    pub external: Vec<String>,
    pub no_ignore: bool,
    pub findings: FindingFlags,
}

impl Config {
    /// METHOD: Resolve the settings for a root: the defaults, then
    /// ghostcode.toml where it exists, then the flags on top. A flag
    /// the user did not pass states nothing, which is what keeps a
    /// file's value reachable from inside Vim, where the plugin passes
    /// a flag only for a setting the user actually set.
    ///
    /// # Errors
    /// When ghostcode.toml exists and cannot be read or parsed.
    pub fn load(root: &Path, args: &Args) -> anyhow::Result<Self> {
        let path = root.join(FILE);

        let file = if path.is_file() {
            let text = std::fs::read_to_string(&path)
                .with_context(|| format!("{}: cannot be read", path.display()))?;
            toml::from_str(&text)
                .with_context(|| format!("{}: cannot be parsed", path.display()))?
        } else {
            FileCfg::default()
        };

        Ok(Self {
            exports_are_api: args.exports_are_api.unwrap_or(file.exports_are_api),
            ignore: file.ignore,
            entry: file.entry,
            external: file.external,
            no_ignore: args.no_ignore,
            findings: FindingFlags {
                write_only: args.findings.write_only.unwrap_or(file.findings.write_only),
                locals: args.findings.locals.unwrap_or(file.findings.locals),
                globals: args.findings.globals.unwrap_or(file.findings.globals),
                buffer_vars: args
                    .findings
                    .buffer_vars
                    .unwrap_or(file.findings.buffer_vars),
                window_vars: args
                    .findings
                    .window_vars
                    .unwrap_or(file.findings.window_vars),
                tab_vars: args.findings.tab_vars.unwrap_or(file.findings.tab_vars),
            },
        })
    }
}
