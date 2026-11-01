//! Vim9 references: what a statement uses, and what it only mentions.
//!
//! License: GNU GPL 3.0

mod common;

use common::source;
use ghostcode::lang::vim9::Vim9;
use ghostcode::lang::Lang;
use ghostcode::model::Analysis;
use ghostcode::model::Reference;

/// FUNCTION: Every reference one file makes.
fn refs(text: &str) -> Vec<Reference> {
    let mut found = Analysis::default();
    Vim9.scan(&source("autoload/p.vim", text), &mut found)
        .expect("a scan never fails on one file");
    found.refs
}

/// FUNCTION: The names one file refers to.
fn names(text: &str) -> Vec<String> {
    refs(text).into_iter().map(|r| r.name).collect()
}

/// FUNCTION: The receiver recorded for a named reference.
fn recv_of(text: &str, name: &str) -> Option<String> {
    refs(text)
        .into_iter()
        .find(|r| r.name == name)
        .unwrap_or_else(|| panic!("no reference to {name}"))
        .recv
}

#[test]
fn a_direct_call_is_a_reference() {
    assert!(names("vim9script\ndef F()\n  Helper()\nenddef\n").contains(&"Helper".to_string()));
}

#[test]
fn a_dotted_call_records_its_receiver() {
    let text = "vim9script\ndef F()\n  menu.Open()\nenddef\n";

    assert_eq!(recv_of(text, "Open"), Some("menu".to_string()));
}

#[test]
fn a_call_on_this_records_its_class_as_the_receiver() {
    let text = "vim9script\nclass C\n  def F()\n    this.Shut()\n  enddef\nendclass\n";

    assert_eq!(
        recv_of(text, "Shut"),
        Some("C".to_string()),
        "the receiver is the type, which for this is the class"
    );
}

#[test]
fn a_bare_funcref_is_a_reference() {
    assert!(names("vim9script\nvar Ref = Handler\n").contains(&"Handler".to_string()));
}

#[test]
fn a_callback_option_is_a_reference() {
    let text = "vim9script\ndef F()\n  popup_create(x, {callback: OnDone})\nenddef\n";

    assert!(names(text).contains(&"OnDone".to_string()));
}

#[test]
fn a_funcref_passed_to_a_builtin_is_a_reference() {
    let text = "vim9script\ndef F()\n  timer_start(1000, Tick)\nenddef\n";

    assert!(names(text).contains(&"Tick".to_string()));
}

#[test]
fn call_with_a_string_literal_is_a_reference() {
    let text = "vim9script\ndef F()\n  call('Helper', [])\nenddef\n";

    assert!(names(text).contains(&"Helper".to_string()));
}

#[test]
fn function_with_a_string_literal_is_a_reference() {
    let text = "vim9script\nvar Ref = function('Helper')\n";

    assert!(names(text).contains(&"Helper".to_string()));
}

#[test]
fn execute_with_a_string_literal_is_a_reference() {
    let text = "vim9script\ndef F()\n  execute('Helper()')\nenddef\n";

    assert!(names(text).contains(&"Helper".to_string()));
}

#[test]
fn an_identifier_inside_an_ordinary_string_is_not_a_reference() {
    let text = "vim9script\ndef F()\n  echo 'Helper is a word here'\nenddef\n";

    assert!(
        !names(text).contains(&"Helper".to_string()),
        "a word in a message is not a call: {:?}",
        names(text)
    );
}

#[test]
fn a_type_annotation_references_its_type() {
    assert!(names("vim9script\nvar x: Config\n").contains(&"Config".to_string()));
}

#[test]
fn a_return_type_references_its_type() {
    let text = "vim9script\ndef F(): Config\nenddef\n";

    assert!(names(text).contains(&"Config".to_string()));
}

#[test]
fn a_generic_type_argument_references_its_type() {
    assert!(names("vim9script\nvar xs: list<Item>\n").contains(&"Item".to_string()));
}

#[test]
fn a_name_in_a_parameter_default_is_a_reference() {
    let text = "vim9script\ndef F(x = Fallback())\nenddef\n";

    assert!(names(text).contains(&"Fallback".to_string()));
}

#[test]
fn a_name_in_a_concatenation_is_a_reference() {
    let text = "vim9script\ndef F()\n  echo PREFIX .. name\nenddef\n";

    assert!(names(text).contains(&"PREFIX".to_string()));
}

#[test]
fn the_autoload_calling_convention_is_one_reference() {
    let text = "vim9script\ndef F()\n  bartleby#Open()\nenddef\n";

    assert!(
        names(text).contains(&"bartleby#Open".to_string()),
        "{:?}",
        names(text)
    );
}

#[test]
fn an_enum_value_records_its_enum_as_the_receiver() {
    let text = "vim9script\ndef F()\n  var c = Color.Red\nenddef\n";

    assert_eq!(recv_of(text, "Red"), Some("Color".to_string()));
}

#[test]
fn a_declaration_does_not_reference_itself() {
    let text = "vim9script\ndef Helper()\nenddef\n";

    assert!(
        !names(text).contains(&"Helper".to_string()),
        "a def is not its own caller: {:?}",
        names(text)
    );
}

#[test]
fn a_reference_in_a_body_carries_the_symbol_that_holds_it() {
    let text = "vim9script\ndef Outer()\n  Inner()\nenddef\n";
    let r = refs(text)
        .into_iter()
        .find(|r| r.name == "Inner")
        .expect("the call to Inner");

    assert_eq!(
        r.origin.expect("an origin").to_string(),
        "autoload/p.vim::Outer"
    );
}

#[test]
fn a_reference_at_the_top_level_belongs_to_the_script() {
    let text = "vim9script\nStart()\n";
    let r = refs(text)
        .into_iter()
        .find(|r| r.name == "Start")
        .expect("the call to Start");

    assert_eq!(
        r.origin.expect("an origin").to_string(),
        "autoload/p.vim::<script>"
    );
}

#[test]
fn exists_with_a_scoped_name_is_a_reference() {
    let text = "vim9script\nif exists('s:is_loaded')\n  finish\nendif\nvar is_loaded = true\n";

    assert!(
        names(text).contains(&"is_loaded".to_string()),
        "the guard every script opens with reads the variable: {:?}",
        names(text)
    );
}

#[test]
fn an_interpolated_name_is_a_reference() {
    let text = "vim9script\nconst LABEL = 'x'\ndef F()\n  echo $'see {LABEL} here'\nenddef\n";

    assert!(
        names(text).contains(&"LABEL".to_string()),
        "a name used only inside interpolation is used: {:?}",
        names(text)
    );
}
