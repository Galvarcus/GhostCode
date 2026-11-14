//! Vim9 declarations: what a file declares, and what it does not.
//!
//! License: GNU GPL 3.0

mod common;

use std::path::Path;

use common::cfg;
use common::source;
use ghostcode::lang::vim9::Vim9;
use ghostcode::lang::Lang;
use ghostcode::model::Analysis;
use ghostcode::model::Kind;

/// FUNCTION: Scan one file and return what it declared.
fn scan(rel: &str, text: &str) -> Analysis {
    let mut found = Analysis::default();
    Vim9.scan(&source(rel, text), &mut found)
        .expect("a scan never fails on one file");
    found
}

/// FUNCTION: Each declaration as `kind name`, in the order found.
fn decls(a: &Analysis) -> Vec<String> {
    a.syms
        .iter()
        .map(|s| format!("{} {}", s.kind, s.name))
        .collect()
}

#[test]
fn def_and_export_def_are_functions() {
    let a = scan(
        "autoload/p.vim",
        "vim9script\ndef Private()\nenddef\nexport def Public()\nenddef\n",
    );

    assert_eq!(decls(&a), vec!["function Private", "function Public"]);
    assert!(!a.syms[0].exported);
    assert!(a.syms[1].exported);
}

#[test]
fn a_class_is_recorded_with_its_extends_and_implements() {
    let a = scan(
        "autoload/p.vim",
        "vim9script\nexport class Item extends Base implements Thing\nendclass\n",
    );

    assert_eq!(decls(&a), vec!["class Item"]);
    assert!(a.syms[0].exported);
    assert_eq!(a.syms[0].line, 2);
}

#[test]
fn enum_values_are_symbols_owned_by_their_enum() {
    let a = scan(
        "autoload/p.vim",
        "vim9script\nenum Color\n  Red, Green\n  Blue('b')\nendenum\n",
    );

    assert_eq!(
        decls(&a),
        vec![
            "enum Color",
            "enum_value Red",
            "enum_value Green",
            "enum_value Blue",
        ]
    );
    assert_eq!(a.syms[1].owner.as_deref(), Some("Color"));
}

#[test]
fn a_method_and_a_static_method_belong_to_their_class() {
    let a = scan(
        "autoload/p.vim",
        "vim9script\nclass Menu\n  def Open()\n  enddef\n  static def Make()\n  enddef\nendclass\n",
    );

    assert_eq!(decls(&a), vec!["class Menu", "method Open", "method Make"]);
    assert_eq!(a.syms[1].owner.as_deref(), Some("Menu"));
    assert_eq!(a.syms[2].owner.as_deref(), Some("Menu"));
}

#[test]
fn a_member_of_an_exported_class_is_api_unless_underscored() {
    let a = scan(
        "autoload/p.vim",
        "vim9script\nexport class Menu\n  var width: number\n  var _depth: number\n  def Open()\n  enddef\n  def _Shut()\n  enddef\nendclass\n",
    );

    assert_eq!(
        decls(&a),
        vec![
            "class Menu",
            "field width",
            "field _depth",
            "method Open",
            "method _Shut",
        ]
    );

    let api: Vec<bool> = a.syms.iter().map(|s| Vim9.is_api(s, &cfg(true))).collect();
    assert_eq!(api, vec![true, true, false, true, false]);
}

#[test]
fn nothing_is_api_when_the_setting_is_off() {
    let a = scan(
        "autoload/p.vim",
        "vim9script\nexport def Public()\nenddef\n",
    );

    assert!(!Vim9.is_api(&a.syms[0], &cfg(false)));
}

/// A local is a declaration now, and what tells it from a script
/// variable is the scope it carries rather than its absence.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn a_script_level_var_is_a_variable_and_a_local_var_is_scoped_to_its_body() {
    let a = scan(
        "autoload/p.vim",
        "vim9script\nvar count = 0\ndef F()\n  var local = 1\nenddef\n",
    );

    assert_eq!(
        decls(&a),
        vec!["variable count", "function F", "variable local"]
    );

    let script = a.syms.iter().find(|s| s.name == "count").expect("count");
    let body = a.syms.iter().find(|s| s.name == "local").expect("local");

    assert!(script.scope.is_none(), "a script variable has no scope");
    assert_eq!(
        body.scope.as_ref().map(ToString::to_string),
        Some("autoload/p.vim::F".to_string())
    );
}

#[test]
fn an_interface_signature_declares_no_symbol_of_its_own() {
    let a = scan(
        "autoload/p.vim",
        "vim9script\nexport interface Thing\n  def Do()\nendinterface\n",
    );

    assert_eq!(
        decls(&a),
        vec!["interface Thing"],
        "the implementations carry the methods"
    );
}

#[test]
fn an_interface_field_after_a_signature_is_still_declared() {
    let a = scan(
        "autoload/p.vim",
        "vim9script\nexport interface Thing\n  def Do()\n  var width: number\nendinterface\n",
    );

    assert_eq!(
        decls(&a),
        vec!["interface Thing", "field width"],
        "a signature opens no body, so the field after it is the interface's"
    );
}

#[test]
fn a_field_after_an_abstract_signature_is_still_declared() {
    let a = scan(
        "autoload/p.vim",
        "vim9script\nabstract class Base\n  abstract def M()\n  var width: number\nendclass\n",
    );

    assert_eq!(
        decls(&a),
        vec!["class Base", "method M", "field width"],
        "an abstract method opens no body either"
    );
}

#[test]
fn an_entry_script_directory_roots_its_top_level_code() {
    let root = Path::new("/project");

    assert!(Vim9.is_entry(root, Path::new("plugin/p.vim")));
    assert!(Vim9.is_entry(root, Path::new("tests/test_p.vim")));
    assert!(Vim9.is_entry(root, Path::new("after/syntax/p.vim")));
    assert!(!Vim9.is_entry(root, Path::new("autoload/p.vim")));
    assert!(!Vim9.is_entry(root, Path::new("import/p.vim")));
}

/// Many plugins keep their tests in `test/`, as five of the eleven in
/// the survey do.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/86
#[test]
fn a_test_directory_of_either_name_roots_its_top_level_code() {
    let root = Path::new("/project");

    assert!(Vim9.is_entry(root, Path::new("tests/test_p.vim")));
    assert!(Vim9.is_entry(root, Path::new("test/test_p.vim")));
}

#[test]
fn a_legacy_function_file_yields_no_symbols_and_no_error() {
    let a = scan(
        "autoload/old.vim",
        "function! s:Helper()\n  echo 'hi'\nendfunction\n",
    );

    assert!(
        decls(&a).is_empty(),
        "legacy script declares no Vim9 symbol"
    );
}

#[test]
fn an_unparseable_line_does_not_lose_the_rest_of_the_file() {
    let a = scan(
        "autoload/p.vim",
        "vim9script\ndef ((((\nenddef\nexport def Good()\nenddef\n",
    );

    assert!(
        decls(&a).contains(&"function Good".to_string()),
        "a broken statement costs its own line only: {:?}",
        decls(&a)
    );
}

#[test]
fn a_declaration_keeps_the_physical_line_it_sits_on() {
    let a = scan(
        "autoload/p.vim",
        "vim9script\n\n\ndef F(\n  x: number\n)\nenddef\n",
    );

    assert_eq!(a.syms[0].line, 4, "the line the def opens on");
    assert_eq!(a.syms[0].kind, Kind::Function);
}

#[test]
fn a_local_after_a_nested_def_is_still_a_local() {
    let a = scan(
        "plugin/main.vim",
        "vim9script\ndef Outer()\n  def Inner()\n  enddef\n  Inner()\n  var local = 1\nenddef\n",
    );

    let local = a
        .syms
        .iter()
        .find(|s| s.name == "local")
        .expect("the local of Outer");

    assert_eq!(
        local.scope.as_ref().map(ToString::to_string),
        Some("plugin/main.vim::Outer".to_string()),
        "the nested enddef closed Inner, not Outer"
    );
}

/// `def g:Name()` declares a global function. The scope letter is
/// Vim's, and the name behind it is the function.
#[test]
fn a_def_behind_the_global_scope_is_a_function_of_its_own_name() {
    let a = scan(
        "tests/t.vim",
        "vim9script\ndef g:Capture(): void\n  echo 1\nenddef\n",
    );

    assert_eq!(decls(&a), vec!["function Capture"]);
}

#[test]
fn the_name_of_a_def_behind_the_global_scope_is_no_reference_to_itself() {
    let a = scan(
        "tests/t.vim",
        "vim9script\ndef g:Capture(): void\n  echo 1\nenddef\n",
    );

    assert!(a.refs.iter().all(|r| r.name != "Capture"));
}

/// The body of such a def belongs to the function, so a variable it
/// declares is scoped to that name.
#[test]
fn a_variable_in_a_def_behind_the_global_scope_is_scoped_to_the_function() {
    let a = scan(
        "tests/t.vim",
        "vim9script\ndef g:Capture(): void\n  var row = 1\n  echo row\nenddef\n",
    );

    assert!(a
        .syms
        .iter()
        .any(|s| s.id.to_string() == "tests/t.vim::Capture.row"));
}

/// FUNCTION: Each class that extends another, as `class base`.
fn heirs(a: &Analysis) -> Vec<String> {
    a.heirs
        .iter()
        .map(|(class, base)| format!("{class} {base}"))
        .collect()
}

/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/82
#[test]
fn a_class_that_extends_another_states_it() {
    let a = scan(
        "autoload/p.vim",
        "vim9script\nabstract class Base\nendclass\nexport class Leaf extends Base implements Shape\nendclass\n",
    );

    assert_eq!(heirs(&a), vec!["Leaf Base"]);
}

#[test]
fn a_class_that_extends_one_behind_an_alias_states_the_class() {
    let a = scan(
        "autoload/p.vim",
        "vim9script\nclass Leaf extends M.Base\nendclass\n",
    );

    assert_eq!(heirs(&a), vec!["Leaf Base"]);
}

#[test]
fn a_class_that_extends_nothing_states_nothing() {
    let a = scan(
        "autoload/p.vim",
        "vim9script\nclass Leaf implements Shape\nendclass\n",
    );

    assert!(heirs(&a).is_empty());
}

/// FUNCTION: The id of each root a scan of one file gives, as text.
fn roots(a: &Analysis) -> Vec<String> {
    a.roots.iter().map(|r| r.to_string()).collect()
}

/// A runner finds each test by its name, as Vim's own tests are found.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/101
#[test]
fn a_test_function_in_a_test_directory_is_a_root() {
    let a = scan(
        "test/t.vim",
        "vim9script\ndef Test_one()\nenddef\ndef g:Test_two()\nenddef\ndef Helper()\nenddef\n",
    );

    assert_eq!(
        roots(&a),
        vec!["test/t.vim::Test_one", "test/t.vim::Test_two"]
    );
}

#[test]
fn a_test_function_outside_a_test_directory_is_no_root() {
    let a = scan("autoload/t.vim", "vim9script\ndef Test_one()\nenddef\n");

    assert!(roots(&a).is_empty(), "{:?}", roots(&a));
}

#[test]
fn a_method_named_as_a_test_is_no_root() {
    let a = scan(
        "tests/t.vim",
        "vim9script\nclass C\n  def Test_one()\n  enddef\nendclass\n",
    );

    assert!(roots(&a).is_empty(), "{:?}", roots(&a));
}

/// Any user or plugin can call a global function, as it can an export.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/102
#[test]
fn a_global_function_counts_as_exported() {
    let a = scan(
        "plugin/p.vim",
        "vim9script\ndef g:Api()\nenddef\ndef Local()\nenddef\n",
    );

    let exported: Vec<(&str, bool)> = a
        .syms
        .iter()
        .map(|s| (s.name.as_str(), s.exported))
        .collect();
    assert_eq!(exported, vec![("Api", true), ("Local", false)]);
}
