//! Vim9's own rules: which files a host sources, and what counts as
//! public API.
//!
//! License: GNU GPL 3.0

use std::path::Path;

use crate::config::Config;
use crate::model::Symbol;

// The directories whose scripts Vim sources by itself, plus tests,
// which a test runner sources. Top-level code in one of them needs no
// caller, so it roots everything it reaches.
const ENTRY_DIRS: &[&str] = &[
    "plugin", "ftplugin", "ftdetect", "syntax", "indent", "compiler", "colors", "keymap", "lang",
    "tests",
];

/// FUNCTION: True when Vim, or a test runner, sources this file
/// directly. The rule is relative to the scanned root, so a vendored
/// copy of another plugin under `deps/` roots nothing: its own
/// `plugin/` directory is not the root's.
pub fn is_entry(file: &Path) -> bool {
    let mut parts = file.components().map(|c| c.as_os_str().to_string_lossy());

    let Some(first) = parts.next() else {
        return false;
    };

    // `after/plugin/x.vim` is sourced exactly as `plugin/x.vim` is.
    let dir = if first == "after" {
        match parts.next() {
            Some(second) => second,
            None => return false,
        }
    } else {
        first
    };

    ENTRY_DIRS.contains(&dir.as_ref())
}

/// FUNCTION: True when a symbol counts as public API, so that nothing
/// reports it.
///
/// Whether a member of an exported class is itself exported is decided
/// when it is declared, where the class's own exportedness is known, so
/// this is the one setting and nothing more. Vim9 cannot export a
/// method or a field by itself, so the declaration applies the
/// language's own convention there: a leading underscore is private.
pub fn is_api(sym: &Symbol, cfg: &Config) -> bool {
    cfg.exports_are_api && sym.exported
}
