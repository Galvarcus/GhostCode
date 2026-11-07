//! The autocommand line: which of its words are Vim's own, and where
//! the command it runs begins.
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

#[test]
fn an_event_name_is_not_a_reference() {
    let text = "vim9script\nautocmd BufEnter * Fn()\n";

    assert_eq!(count(text, "BufEnter"), 0);
    assert_eq!(count(text, "Fn"), 1);
}

/// A user event's name is the plugin's own vocabulary: it credits no
/// symbol, even one that carries the same spelling.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn a_user_events_name_credits_nothing() {
    let text = "vim9script\nclass Save\nendclass\nautocmd User Save Fn()\n";

    assert_eq!(count(text, "Save"), 0);
}

#[test]
fn a_group_is_not_a_reference() {
    let text = "vim9script\ndoautocmd Powerline ColorScheme\n";

    assert_eq!(count(text, "Powerline"), 0);
}

#[test]
fn a_group_name_on_an_augroup_line_is_still_dropped() {
    let text = "vim9script\naugroup bartleby_focus\naugroup END\n";

    assert_eq!(count(text, "bartleby_focus"), 0);
}

#[test]
fn a_pattern_is_not_a_reference() {
    let text = "vim9script\nautocmd BufRead *.fountain Fn()\n";

    assert_eq!(count(text, "fountain"), 0);
}

/// The text after the pattern is a command line of its own, so its
/// first word is where Vim reads a command.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn a_command_at_the_head_of_a_body_is_vims() {
    let text = "vim9script\nautocmd InsertLeave <buffer> set formatoptions-=a\n";

    assert_eq!(count(text, "set"), 0);
}

#[test]
fn a_call_in_a_body_keeps_its_reference() {
    let text = "vim9script\nautocmd BufRead * Fn()\n";

    assert_eq!(count(text, "Fn"), 1);
}

#[test]
fn a_variable_read_in_a_body_keeps_its_reference() {
    let text = "vim9script\nvar flag = 1\nautocmd BufRead * echo flag\n";

    assert_eq!(count(text, "flag"), 1);
}
