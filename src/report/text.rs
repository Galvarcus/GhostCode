//! The text form: one line per finding, as the quickfix list reads it.
//!
//! License: GNU GPL 3.0

use std::fmt::Write;

use super::Report;

/// FUNCTION: The report as lines of `file:line:col:[class] kind name`.
///
/// This is the line Vim's own workflow writes out of the quickfix
/// list, and the line CI counts, so its shape is a contract. Only a
/// ghost carries the `[ghost]` tag: a finding of another class carries
/// its own, so that a new class cannot be counted as a ghost.
pub fn text(r: &Report) -> String {
    let mut out = String::new();

    for f in &r.findings {
        let _ = writeln!(
            out,
            "{}:{}:{}:[{}] {} {}",
            f.file.display(),
            f.line,
            f.col,
            f.class,
            f.kind,
            f.name
        );
    }

    out
}
