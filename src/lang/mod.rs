//! The language boundary: what a language's syntax means, and nothing
//! about reachability.
//!
//! License: GNU GPL 3.0

use std::path::Path;
use std::path::PathBuf;

pub mod vim9;

use crate::config::Config;
use crate::model::Sink;
use crate::model::Symbol;
use crate::project::Source;

/// TRAIT: One language. Everything a language knows lives behind this:
/// how its declarations and references look, which of its files a host
/// sources directly, how an import names a file, and when a symbol is
/// public API. Resolution and reachability know none of it.
pub trait Lang: Sync {
    fn name(&self) -> &'static str;

    fn extensions(&self) -> &[&'static str];

    /// METHOD: True when the host sources this file directly, so its
    /// top-level code is a root that needs no caller.
    fn is_entry(&self, root: &Path, file: &Path) -> bool;

    /// METHOD: Emit every declaration and every reference in one file.
    ///
    /// # Errors
    /// Never for a file it cannot parse: an unparseable construct is
    /// skipped so that the rest of the project still scans.
    fn scan(&self, src: &Source, out: &mut dyn Sink) -> anyhow::Result<()>;

    /// METHOD: True when this symbol counts as public API, so that it
    /// is never reported.
    fn is_api(&self, sym: &Symbol, cfg: &Config) -> bool;

    /// METHOD: True when the run asked for findings on the symbols
    /// that belong to no file and that this spelling names. The
    /// spelling is a symbol's name, or the start that a group of them
    /// shares. A language with no such symbol answers false.
    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/55
    fn shared_on(&self, _name: &str, _cfg: &Config) -> bool {
        false
    }

    /// METHOD: The file and the symbol a name states by its spelling
    /// alone, with no import, relative to the root. A language with
    /// no such name answers nothing.
    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/65
    fn stated<'n>(&self, _name: &'n str) -> Option<(PathBuf, &'n str)> {
        None
    }
}

/// FUNCTION: The language that claims a file, by its extension.
pub fn for_path(path: &Path) -> Option<&'static dyn Lang> {
    let ext = path.extension()?.to_str()?;
    registry()
        .iter()
        .copied()
        .find(|lang| lang.extensions().contains(&ext))
}

/// FUNCTION: Every language the binary knows.
fn registry() -> &'static [&'static dyn Lang] {
    &[&vim9::Vim9]
}
