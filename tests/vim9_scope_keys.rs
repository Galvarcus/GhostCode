//! The scope key: which body a reference is made from, so that a
//! variable of that body can be told from a name the whole file sees.
//!
//! License: GNU GPL 3.0

mod common;

use common::source;
use ghostcode::lang::vim9::Vim9;
use ghostcode::lang::Lang;
use ghostcode::model::Analysis;

/// FUNCTION: The origin recorded for the one reference of a name.
fn origin(text: &str, name: &str) -> String {
    let mut found = Analysis::default();
    Vim9.scan(&source("autoload/p.vim", text), &mut found)
        .expect("a scan never fails on one file");

    found
        .refs
        .iter()
        .find(|r| r.name == name)
        .unwrap_or_else(|| panic!("no reference named {name}"))
        .origin
        .as_ref()
        .map(ToString::to_string)
        .unwrap_or_default()
}

#[test]
fn a_reference_in_a_body_carries_that_body_as_its_origin() {
    let text = "vim9script\ndef F()\n  Call()\nenddef\n";

    assert_eq!(origin(text, "Call"), "autoload/p.vim::F");
}

/// A def may hold a def, and one `enddef` closes one body. Resetting
/// to the script on the inner one records the outer body's work as
/// the file's own, which is a reachability edge from the wrong node.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn a_reference_after_a_nested_def_still_carries_the_outer_body() {
    let text = "vim9script\ndef F()\n  def G()\n  enddef\n  Call()\nenddef\n";

    assert_eq!(origin(text, "Call"), "autoload/p.vim::F");
}

#[test]
fn a_reference_in_a_method_carries_the_class_in_its_origin() {
    let text = "vim9script\nclass C\n  def M()\n    Call()\n  enddef\nendclass\n";

    assert_eq!(origin(text, "Call"), "autoload/p.vim::C.M");
}

#[test]
fn a_reference_at_script_level_carries_the_script() {
    let text = "vim9script\nCall()\n";

    assert_eq!(origin(text, "Call"), "autoload/p.vim::<script>");
}
