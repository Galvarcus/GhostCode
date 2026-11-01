//! Vim9 type tracking: what a receiver's type is, where it can be told.
//!
//! License: GNU GPL 3.0

mod common;

use common::source;
use ghostcode::lang::vim9::Vim9;
use ghostcode::lang::Lang;
use ghostcode::model::Analysis;

/// FUNCTION: The receiver recorded for a reference to a name.
fn recv_of(text: &str, name: &str) -> Option<String> {
    let mut found = Analysis::default();
    Vim9.scan(&source("autoload/p.vim", text), &mut found)
        .expect("a scan never fails on one file");

    found
        .refs
        .into_iter()
        .find(|r| r.name == name)
        .unwrap_or_else(|| panic!("no reference to {name}"))
        .recv
}

#[test]
fn a_declared_local_gives_its_method_the_receiver_type() {
    let text = "vim9script\ndef F()\n  var menu: Menu\n  menu.Open()\nenddef\n";

    assert_eq!(recv_of(text, "Open"), Some("Menu".to_string()));
}

#[test]
fn a_constructor_assignment_gives_the_variable_its_type() {
    let text = "vim9script\ndef F()\n  var menu = Menu.new()\n  menu.Open()\nenddef\n";

    assert_eq!(recv_of(text, "Open"), Some("Menu".to_string()));
}

#[test]
fn a_parameter_type_gives_its_method_the_receiver_type() {
    let text = "vim9script\ndef F(menu: Menu)\n  menu.Open()\nenddef\n";

    assert_eq!(recv_of(text, "Open"), Some("Menu".to_string()));
}

#[test]
fn this_resolves_to_the_enclosing_class() {
    let text = "vim9script\nclass Popup\n  def F()\n    this.Shut()\n  enddef\nendclass\n";

    assert_eq!(recv_of(text, "Shut"), Some("Popup".to_string()));
}

#[test]
fn a_class_field_type_resolves_a_this_field_method() {
    let text = "vim9script\nclass Popup\n  var menu: Menu\n  def F()\n    this.menu.Open()\n  enddef\nendclass\n";

    assert_eq!(recv_of(text, "Open"), Some("Menu".to_string()));
}

#[test]
fn a_method_on_a_constructor_result_resolves_to_that_class() {
    let text = "vim9script\ndef F()\n  Menu.new(x).Open()\nenddef\n";

    assert_eq!(recv_of(text, "Open"), Some("Menu".to_string()));
}

#[test]
fn a_module_level_variable_type_resolves_its_method() {
    let text = "vim9script\nvar log: Logger\ndef F()\n  log.Info('x')\nenddef\n";

    assert_eq!(recv_of(text, "Info"), Some("Logger".to_string()));
}

#[test]
fn an_untyped_receiver_leaves_the_type_unknown() {
    let text = "vim9script\ndef F(menu)\n  menu.Open()\nenddef\n";

    assert_eq!(
        recv_of(text, "Open"),
        None,
        "with no type, resolution falls back to the name alone"
    );
}

#[test]
fn a_class_name_used_directly_stays_the_receiver() {
    let text = "vim9script\ndef F()\n  var c = Color.Red\nenddef\n";

    assert_eq!(
        recv_of(text, "Red"),
        Some("Color".to_string()),
        "an enum value names its enum"
    );
}

#[test]
fn a_local_shadows_nothing_outside_its_own_body() {
    let text =
        "vim9script\ndef F()\n  var menu: Menu\nenddef\ndef G(menu)\n  menu.Open()\nenddef\n";

    assert_eq!(
        recv_of(text, "Open"),
        None,
        "F's local says nothing about G's parameter"
    );
}
