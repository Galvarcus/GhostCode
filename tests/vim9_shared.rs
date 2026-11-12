//! Scoped variables: what a write and a read of a variable in `g:`,
//! `b:`, `w:` or `t:` make the scan emit.
//!
//! License: GNU GPL 3.0

mod common;

use common::source;
use ghostcode::lang::vim9::Vim9;
use ghostcode::lang::Lang;
use ghostcode::model::Analysis;
use ghostcode::model::Kind;
use ghostcode::model::Reference;
use ghostcode::model::SymbolId;

/// FUNCTION: Everything one snippet emits.
fn scan(text: &str) -> Analysis {
    let mut found = Analysis::default();
    Vim9.scan(&source("autoload/p.vim", text), &mut found)
        .expect("a scan never fails on one file");

    found
}

/// FUNCTION: How many references one snippet emits for a name.
fn reads(text: &str, name: &str) -> usize {
    scan(text).refs.iter().filter(|r| r.name == name).count()
}

/// FUNCTION: Whether one snippet declares a variable every file
/// shares, by its full spelling.
fn declares(text: &str, name: &str) -> bool {
    scan(text)
        .syms
        .iter()
        .any(|s| s.id == SymbolId::shared(name))
}

/// FUNCTION: The reference one snippet emits for a name.
fn one(text: &str, name: &str) -> Reference {
    scan(text)
        .refs
        .into_iter()
        .find(|r| r.name == name)
        .unwrap_or_else(|| panic!("no reference named {name}"))
}

/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/55
#[test]
fn a_variable_the_help_documents_is_vims_own() {
    let text = "vim9script\ndef F()\n  echo b:changedtick\nenddef\n";

    assert!(one(text, "b:changedtick").owned);
}

/// A name that is read and never written has no symbol to take the
/// read, and it is no gap either: the variable is another plugin's,
/// or the user's.
#[test]
fn a_variable_the_project_never_writes_is_no_unplaced_name() {
    let text = "vim9script\ndef F()\n  echo b:bartleby_doc\nenddef\n";

    assert!(one(text, "b:bartleby_doc").owned);
}

#[test]
fn a_write_declares_a_shared_variable() {
    let a = scan("vim9script\ng:x = 1\n");
    let s = a.syms.iter().find(|s| s.name == "g:x").expect("a symbol");

    assert_eq!(s.id, SymbolId::shared("g:x"));
    assert_eq!(
        (s.kind, s.line, s.scope.is_none()),
        (Kind::Variable, 2, true)
    );
}

#[test]
fn a_write_is_no_reference() {
    let a = scan("vim9script\ng:x = 1\n");

    assert!(a.refs.iter().all(|r| r.name != "g:x" && r.name != "x"));
}

#[test]
fn a_direct_read_names_the_full_spelling() {
    let r = one("vim9script\ndef F()\n  echo t:y\nenddef\n", "t:y");

    assert!(r.owned && !r.member && r.recv.is_none());
}

#[test]
fn the_bare_name_behind_a_scope_is_not_emitted() {
    assert_eq!(reads("vim9script\ndef F()\n  echo t:y\nenddef\n", "y"), 0);
}

#[test]
fn each_of_the_four_scopes_declares() {
    let text = "vim9script\ng:a = 1\nb:a = 1\nw:a = 1\nt:a = 1\n";

    for name in ["g:a", "b:a", "w:a", "t:a"] {
        assert!(declares(text, name), "{name} is written");
    }
}

#[test]
fn a_script_scope_is_left_as_it_was() {
    let a = scan("s:z = 1\n");

    assert!(a.syms.iter().all(|s| !s.id.is_shared()));
}

#[test]
fn a_legacy_let_is_a_write() {
    assert!(declares("let g:x = 1\n", "g:x"));
}

#[test]
fn a_compound_assignment_is_a_write_and_no_read() {
    let text = "vim9script\ng:x += 1\n";

    assert!(declares(text, "g:x"));
    assert_eq!(reads(text, "g:x"), 0);
}

#[test]
fn a_read_in_the_statement_that_writes_is_dropped() {
    assert_eq!(reads("vim9script\ng:x = !g:x\n", "g:x"), 0);
}

#[test]
fn a_read_behind_a_bar_of_a_write_is_kept() {
    assert_eq!(reads("vim9script\ng:x = 1 | echo g:x\n", "g:x"), 1);
}

#[test]
fn unlet_is_neither_a_write_nor_a_read() {
    let text = "vim9script\nunlet g:x\nunlet! g:y\n";

    assert!(!declares(text, "g:x") && !declares(text, "g:y"));
    assert_eq!(reads(text, "g:x") + reads(text, "g:y"), 0);
    assert_eq!(reads(text, "x") + reads(text, "y"), 0);
}

#[test]
fn a_write_of_vims_own_variable_declares_nothing() {
    assert!(!declares(
        "vim9script\nb:current_syntax = 'x'\n",
        "b:current_syntax"
    ));
}

/// The variable holds a dictionary or a list, and the statement
/// changes what it holds. The variable itself is read to do that.
#[test]
fn a_write_through_a_key_reads_the_variable() {
    for text in ["vim9script\ng:x.key = 1\n", "vim9script\ng:x[0] = 1\n"] {
        assert!(!declares(text, "g:x"), "{text}");
        assert_eq!(reads(text, "g:x"), 1, "{text}");
    }
}

#[test]
fn a_comparison_is_a_read() {
    let text = "vim9script\nif g:x == 1\nendif\n";

    assert!(!declares(text, "g:x"));
    assert_eq!(reads(text, "g:x"), 1);
}

/// A funcref held in a shared variable is read where it is called. A
/// legacy function declared as `g:Name` is called the same way, and
/// its bare name still credits the function.
#[test]
fn a_call_through_a_scope_reads_the_variable_and_keeps_the_bare_name() {
    let text = "vim9script\ndef F()\n  g:Hook()\nenddef\n";

    assert_eq!(reads(text, "g:Hook"), 1);
    assert_eq!(reads(text, "Hook"), 1);
}

/// `&g:textwidth` is the global value of an option. The letter there
/// is a scope of the option, and no variable is named.
#[test]
fn an_option_behind_a_scope_is_no_variable() {
    let text = "vim9script\n&g:textwidth = 80\necho &l:textwidth\n";

    assert!(scan(text).syms.iter().all(|s| !s.id.is_shared()));
    assert_eq!(reads(text, "g:textwidth"), 0);
}
