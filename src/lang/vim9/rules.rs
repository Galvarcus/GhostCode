//! Vim9's own rules: which files a host sources, what counts as
//! public API, and which file an autoload name states.
//!
//! License: GNU GPL 3.0

use std::path::Path;
use std::path::PathBuf;

use crate::config::Config;
use crate::model::Symbol;

// The directories whose scripts Vim sources by itself, plus tests,
// which a test runner sources. Top-level code in one of them needs no
// caller, so it roots everything it reaches.
const ENTRY_DIRS: &[&str] = &[
    "plugin", "ftplugin", "ftdetect", "syntax", "indent", "compiler", "colors", "keymap", "lang",
    "tests",
];

// What ends the name of a script.
pub const SCRIPT_EXT: &str = "vim";

// What divides the parts of a classic autoload name, and the directory
// those parts are a path under.
const AUTOLOAD_SEP: char = '#';
const AUTOLOAD_DIR: &str = "autoload";

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

// What stands for any run of characters in a pattern of names.
const ANY: char = '*';

/// FUNCTION: Whether the run asked for findings on the scoped
/// variable a spelling names, as `g:width`, or on the scope it opens
/// with, as `g:`.
///
/// Each scope has a flag of its own. A name the project lists as
/// written for a reader outside it is never reported, whatever the
/// flag says.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/55
pub fn shared_on(name: &str, cfg: &Config) -> bool {
    let on = match name.chars().next() {
        Some('g') => cfg.findings.globals,
        Some('b') => cfg.findings.buffer_vars,
        Some('w') => cfg.findings.window_vars,
        Some('t') => cfg.findings.tab_vars,
        _ => false,
    };

    on && !cfg.external.iter().any(|pat| fits(pat, name))
}

/// FUNCTION: Whether a name fits a pattern in which `*` stands for
/// any run of characters, and every other character for itself.
pub fn fits(pat: &str, name: &str) -> bool {
    let mut parts = pat.split(ANY);
    let first = parts.next().unwrap_or_default();

    let Some(mut rest) = name.strip_prefix(first) else {
        return false;
    };

    let mut last = None;

    for part in parts {
        if let Some(prev) = last.replace(part) {
            let Some(at) = rest.find(prev) else {
                return false;
            };
            rest = &rest[at + prev.len()..];
        }
    }

    match last {
        Some(end) => rest.ends_with(end),
        None => rest.is_empty(),
    }
}

/// FUNCTION: The file and the function a classic autoload name
/// states, as `foo#bar#Func` states `autoload/foo/bar.vim` and `Func`.
pub fn autoload_parts(name: &str) -> Option<(PathBuf, &str)> {
    let (prefix, func) = name.rsplit_once(AUTOLOAD_SEP)?;
    let path = PathBuf::from(AUTOLOAD_DIR)
        .join(prefix.replace(AUTOLOAD_SEP, "/"))
        .with_extension(SCRIPT_EXT);

    Some((path, func))
}

#[cfg(test)]
mod shared_tests {
    use super::fits;

    #[test]
    fn a_star_fits_any_run_of_characters() {
        assert!(fits("g:tlinks_*", "g:tlinks_items"));
        assert!(fits("g:tlinks_*", "g:tlinks_"));
        assert!(fits("g:*_items", "g:tlinks_items"));
        assert!(fits("g:*link*items", "g:tlinks_items"));
        assert!(!fits("g:tlinks_*", "g:other_items"));
        assert!(!fits("g:*_items", "g:tlinks_item"));
        assert!(!fits("g:*aa*a", "g:aa"));
    }

    #[test]
    fn a_pattern_with_no_star_fits_only_itself() {
        assert!(fits("g:colors", "g:colors"));
        assert!(!fits("g:colors", "g:colors_name"));
        assert!(!fits("g:colors_name", "g:colors"));
    }
}

#[cfg(test)]
mod autoload_tests {
    use std::path::PathBuf;

    use super::autoload_parts;

    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/65
    #[test]
    fn an_autoload_name_states_its_file_and_its_function() {
        assert_eq!(
            autoload_parts("foo#bar#Func"),
            Some((PathBuf::from("autoload/foo/bar.vim"), "Func"))
        );
    }

    #[test]
    fn a_name_with_no_separator_states_no_file() {
        assert_eq!(autoload_parts("Func"), None);
    }
}
