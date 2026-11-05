//! Vim's own functions: which calls the scan keeps out of the
//! reference list because Vim defines the name, not the project.
//!
//! License: GNU GPL 3.0

mod common;

use common::source;
use common::TempDir;
use ghostcode::lang::vim9::Vim9;
use ghostcode::lang::Lang;
use ghostcode::model::Analysis;
use ghostcode::model::Reference;
use ghostcode::report;

/// FUNCTION: Every reference one snippet emits.
fn refs(text: &str) -> Vec<Reference> {
    let mut found = Analysis::default();
    Vim9.scan(&source("autoload/p.vim", text), &mut found)
        .expect("a scan never fails on one file");

    found.refs
}

/// FUNCTION: How many references a snippet emits for one name.
fn count(text: &str, name: &str) -> usize {
    refs(text).iter().filter(|r| r.name == name).count()
}

#[test]
fn a_called_builtin_is_not_a_reference() {
    let text = "vim9script\ndef F(xs: list<string>)\n  echo len(xs)\nenddef\n";

    assert_eq!(count(text, "len"), 0);
}

#[test]
fn a_called_builtin_at_script_level_is_not_a_reference() {
    let text = "vim9script\necho strlen('x')\n";

    assert_eq!(count(text, "strlen"), 0);
}

/// Vim refuses a lowercase `def` and a lowercase funcref variable, so
/// a called lowercase name is Vim's. A name that is not called may
/// still be the project's: a plain variable, a dictionary key, or a
/// class reached through a dot.
#[test]
fn a_builtin_name_that_is_not_called_is_still_a_reference() {
    let text = "vim9script\nvar filter = 1\necho filter\n";

    assert_eq!(count(text, "filter"), 1);
}

#[test]
fn a_method_named_like_a_builtin_is_still_a_reference() {
    let text = "vim9script\ndef F(m: Menu)\n  m.len()\nenddef\n";

    assert_eq!(
        refs(text)
            .iter()
            .find(|r| r.name == "len")
            .and_then(|r| r.recv.clone()),
        Some("Menu".to_string())
    );
}

#[test]
fn a_called_name_vim_does_not_define_is_still_a_reference() {
    let text = "vim9script\ndef F()\n  Helper()\nenddef\n";

    assert_eq!(count(text, "Helper"), 1);
}

/// The reference is dropped rather than marked, and this is what the
/// difference buys. A script variable named like a builtin took a
/// credit from every call of that builtin anywhere in the project,
/// which hid the variable when nothing read it.
#[test]
fn a_variable_named_like_a_builtin_is_reported_when_nothing_reads_it() {
    let dir = TempDir::new("builtin-shadow");
    dir.write(
        "autoload/lib.vim",
        "vim9script\n\
         var filter = 1\n\
         export def Run(xs: list<string>)\n\
         \x20 echo filter(xs, (_, v) => true)\n\
         enddef\n",
    );
    dir.write(
        "plugin/p.vim",
        "vim9script\nimport autoload 'lib.vim' as L\nL.Run([])\n",
    );

    let r = report::analyze(dir.path(), &common::cfg(false)).expect("the scan runs");
    let found: Vec<String> = r
        .findings
        .iter()
        .map(|f| format!("{} {}", f.kind, f.name))
        .collect();

    assert_eq!(found, vec!["variable filter".to_string()]);
}
