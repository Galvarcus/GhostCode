//! Vim's options: the words after a set-family command, and the
//! argument of `exists()`.
//!
//! License: GNU GPL 3.0

mod common;

use common::source;
use ghostcode::lang::vim9::Vim9;
use ghostcode::lang::Lang;
use ghostcode::model::Analysis;
use ghostcode::model::Reference;

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

/// FUNCTION: The reference one snippet emits for a name, with its mark.
fn one(text: &str, name: &str) -> Reference {
    refs(text)
        .into_iter()
        .find(|r| r.name == name)
        .unwrap_or_else(|| panic!("no reference named {name}"))
}

/// An option name, an option's value, and a name the plugin invents
/// for Vim all stand after a set-family command, where nothing the
/// project declares can be meant. They are marked rather than dropped,
/// so a value that names a project function keeps its credit.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn an_option_after_a_set_command_is_marked_as_vims() {
    let text = "vim9script\ndef F()\n  setlocal buftype=nofile\nenddef\n";

    assert!(one(text, "buftype").owned);
    assert!(one(text, "nofile").owned);
}

#[test]
fn a_filetype_the_plugin_invents_is_marked_as_vims() {
    let text = "vim9script\ndef F()\n  setlocal filetype=bartleby\nenddef\n";

    assert!(one(text, "bartleby").owned);
}

#[test]
fn an_abbreviated_set_command_claims_its_arguments() {
    let text = "vim9script\ndef F()\n  setl winfixwidth\nenddef\n";

    assert!(one(text, "winfixwidth").owned);
}

#[test]
fn a_set_command_claims_nothing_past_a_bar() {
    let text = "vim9script\ndef F()\n  setlocal nu | Fn()\nenddef\n";

    assert_eq!(count(text, "Fn"), 1);
    assert!(!one(text, "Fn").owned);
}

/// The claim begins at the set command, not at the head of the
/// statement, so a call before one keeps its credit.
#[test]
fn a_word_before_a_set_command_is_not_its_argument() {
    let text = "vim9script\ndef F()\n  Fn() | setlocal nu\nenddef\n";

    assert!(!one(text, "Fn").owned);
    assert!(one(text, "nu").owned);
}
