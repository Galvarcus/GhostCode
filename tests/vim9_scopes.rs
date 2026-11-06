//! Vim's scope notation: which parts of `v:version` and `g:width`
//! are Vim's own names and which are the project's.
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
fn a_scope_prefix_is_not_a_reference() {
    let text = "vim9script\nif v:version < 902\n  finish\nendif\n";

    assert_eq!(count(text, "v"), 0);
}

/// `v:` is Vim's own namespace, so the name inside it is Vim's too.
#[test]
fn a_name_in_vims_own_scope_is_not_a_reference() {
    let text = "vim9script\nif v:version < 902\n  finish\nendif\n";

    assert_eq!(count(text, "version"), 0);
}

#[test]
fn a_buffer_scope_prefix_is_not_a_reference() {
    let text = "vim9script\ndef F()\n  b:state = 1\nenddef\n";

    assert_eq!(count(text, "b"), 0);
}

/// Every scope but `v:` holds names the project or the user chose, so
/// the name after the colon keeps its reference.
#[test]
fn a_global_the_project_names_is_still_a_reference() {
    let text = "vim9script\ndef F()\n  echo g:plugin_width\nenddef\n";

    assert_eq!(count(text, "g"), 0);
    assert_eq!(count(text, "plugin_width"), 1);
}

/// A ternary puts a name immediately before a colon at the top level
/// of a statement, where nothing may suppress it.
#[test]
fn a_value_before_a_colon_in_a_ternary_is_still_a_reference() {
    let text = "vim9script\ndef F(flag: bool)\n  var w = flag ? Wide : Narrow\nenddef\n";

    assert_eq!(count(text, "Wide"), 1);
    assert_eq!(count(text, "Narrow"), 1);
}

/// A dictionary value sits after a colon as a scoped name does, and a
/// key spelled like a scope letter must not make it look like one.
#[test]
fn a_dictionary_value_after_a_key_named_like_a_scope_is_still_a_reference() {
    let text = "vim9script\ndef F()\n  var d = {v: Wide}\nenddef\n";

    assert_eq!(count(text, "Wide"), 1);
}

#[test]
fn a_dictionary_key_is_not_a_reference() {
    let text = "vim9script\ndef F()\n  var d = {width: 1}\nenddef\n";

    assert_eq!(count(text, "width"), 0);
}

#[test]
fn a_type_in_an_annotation_is_still_a_reference() {
    let text = "vim9script\ndef F()\n  var m: Menu\nenddef\n";

    assert_eq!(count(text, "Menu"), 1);
}
