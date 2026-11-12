//! Scoped variables: what a write and a read of a variable in `g:`,
//! `b:`, `w:` or `t:` make the scan emit.
//!
//! License: GNU GPL 3.0

mod common;

use common::source;
use ghostcode::lang::vim9::Vim9;
use ghostcode::lang::Lang;
use ghostcode::model::Analysis;
use ghostcode::model::Reference;

/// FUNCTION: The reference one snippet emits for a name.
fn one(text: &str, name: &str) -> Reference {
    let mut found = Analysis::default();
    Vim9.scan(&source("autoload/p.vim", text), &mut found)
        .expect("a scan never fails on one file");

    found
        .refs
        .into_iter()
        .find(|r| r.name == name)
        .unwrap_or_else(|| panic!("no reference named {name}"))
}

/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/55
#[test]
fn a_variable_the_help_documents_is_vims_own() {
    let text = "vim9script\ndef F()\n  echo b:changedtick\nenddef\n";

    assert!(one(text, "changedtick").owned);
}

#[test]
fn a_variable_the_help_does_not_document_is_not_marked_yet() {
    let text = "vim9script\ndef F()\n  echo b:bartleby_doc\nenddef\n";

    assert!(!one(text, "bartleby_doc").owned);
}
