//! The variables of a function body: which names the scan keeps out of
//! the reference list because the body itself declares them.
//!
//! A `var` or `const` is no longer one of them. It is a symbol scoped
//! to its body, so its read is a reference that resolves there, and
//! what the old suppression protected is resolution's job now.
//! REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
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

/// A read of the body's own variable is a reference, because the
/// variable is now a symbol for it to resolve to, and that read is
/// the credit keeping it off the report. The false credit the old
/// suppression prevented is prevented by the scope instead, which
/// `tests/vim9_local_symbols.rs` holds.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn a_variable_the_body_declares_is_a_reference_carrying_that_body() {
    let text = "vim9script\ndef F()\n  var row = 1\n  echo row\nenddef\n";

    assert_eq!(count(text, "row"), 1);
    assert_eq!(
        refs(text)
            .iter()
            .find(|r| r.name == "row")
            .and_then(|r| r.origin.as_ref())
            .map(ToString::to_string),
        Some("autoload/p.vim::F".to_string())
    );
}

#[test]
fn a_parameter_is_not_a_reference() {
    let text = "vim9script\ndef F(amt: number)\n  echo amt\nenddef\n";

    assert_eq!(count(text, "amt"), 0);
}

#[test]
fn a_loop_variable_is_not_a_reference() {
    let text = "vim9script\ndef F(xs: list<string>)\n  for f in xs\n    echo f\n  endfor\nenddef\n";

    assert_eq!(count(text, "f"), 0);
}

#[test]
fn an_unpacked_loop_variable_is_not_a_reference() {
    let text = "vim9script\ndef F(d: dict<string>)\n  for [k, v] in items(d)\n    echo k .. v\n  endfor\nenddef\n";

    assert_eq!(count(text, "k"), 0);
    assert_eq!(count(text, "v"), 0);
}

#[test]
fn a_lambda_parameter_is_not_a_reference() {
    let text = "vim9script\ndef F(xs: list<string>)\n  echo xs->mapnew((_, s) => s)\nenddef\n";

    assert_eq!(count(text, "_"), 0);
    assert_eq!(count(text, "s"), 0);
}

/// A lambda's parameters belong to the lambda, not to the body around
/// it, so a name the body uses for its own purpose after one keeps
/// its reference.
#[test]
fn a_lambda_parameter_hides_nothing_after_the_statement() {
    let text = "vim9script\ndef F(xs: list<string>)\n  echo xs->mapnew((_, Fmt) => Fmt)\n  Fmt()\nenddef\n";

    assert_eq!(count(text, "Fmt"), 1);
}

/// The receiver of a member access is the body's own variable, and the
/// member it reaches is still a reference, carrying the type the
/// variable was declared with.
#[test]
fn a_member_of_a_local_receiver_is_still_a_reference() {
    let text = "vim9script\ndef F(m: Menu)\n  m.Open()\nenddef\n";

    assert_eq!(count(text, "m"), 0);
    assert_eq!(
        refs(text)
            .iter()
            .find(|r| r.name == "Open")
            .and_then(|r| r.recv.clone()),
        Some("Menu".to_string())
    );
}

#[test]
fn a_project_function_called_in_a_body_is_still_a_reference() {
    let text = "vim9script\ndef F()\n  Helper()\nenddef\n";

    assert_eq!(count(text, "Helper"), 1);
}

/// A script variable is a symbol of the project, and the reads of it
/// are what credit it. Nothing here may suppress one.
#[test]
fn a_script_variable_read_at_script_level_is_still_a_reference() {
    let text = "vim9script\nvar width = 1\necho width\n";

    assert_eq!(count(text, "width"), 1);
}

#[test]
fn a_script_variable_read_inside_a_body_is_still_a_reference() {
    let text = "vim9script\nvar width = 1\ndef F()\n  echo width\nenddef\n";

    assert_eq!(count(text, "width"), 1);
}

/// `var Menu = Menu.new()` names the class on the right of the
/// assignment, which the declaration on the left must not hide: the
/// class has to keep that credit. The later `Menu.Open()` names the
/// variable holding the object, which is a second reference and
/// resolves to the body's own symbol.
#[test]
fn a_name_the_statement_declares_still_credits_a_symbol_of_that_name() {
    let text = "vim9script\ndef F()\n  var Menu = Menu.new()\n  Menu.Open()\nenddef\n";

    assert_eq!(count(text, "Menu"), 2);
}

/// A parameter list is separated by its own commas. A comma inside a
/// parameter's type separates nothing, and the name after it is a
/// type the project may declare, which must keep its credit.
#[test]
fn a_name_inside_a_parameters_type_is_still_a_reference() {
    let text = "vim9script\ndef Register(Cb: func(string, Config))\nenddef\n";

    assert_eq!(count(text, "Config"), 1);
}

#[test]
fn a_name_inside_a_parameters_default_is_still_a_reference() {
    let text = "vim9script\ndef F(xs = [One, Two])\nenddef\n";

    assert_eq!(count(text, "Two"), 1);
}

#[test]
fn a_parameter_after_a_nested_comma_is_not_a_reference() {
    let text = "vim9script\ndef F(Cb: func(string, Config), amt: number)\n  echo amt\nenddef\n";

    assert_eq!(count(text, "amt"), 0);
}

/// A body outside the one that declared the name knows nothing of it.
/// Both reads are references; only the one inside F has a symbol to
/// reach, which `a_scoped_symbol_is_invisible_from_another_scope` in
/// `src/resolve.rs` holds. G's read resolves to nothing, which is
/// what keeps F's variable off the report rather than crediting it.
#[test]
fn a_variable_of_another_body_is_still_a_reference() {
    let text =
        "vim9script\ndef F()\n  var row = 1\n  echo row\nenddef\ndef G()\n  echo row\nenddef\n";

    assert_eq!(count(text, "row"), 2);
}

/// A lambda written as a block ends where its brace closes, which is
/// several statements on: a declaring word inside the block starts a
/// statement of its own. Its parameters are bound until that brace.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn a_parameter_of_a_block_lambda_is_not_a_reference_in_its_body() {
    let text = "vim9script\ndef F(xs: list<string>)\n  echo xs->mapnew((_, row) => {\n    var s = row\n    return s .. row\n  })\nenddef\n";

    assert_eq!(count(text, "row"), 0);
}

#[test]
fn a_parameter_of_a_block_lambda_hides_nothing_after_the_block() {
    let text = "vim9script\ndef F(xs: list<string>)\n  echo xs->mapnew((_, Fmt) => {\n    return Fmt\n  })\n  Fmt()\nenddef\n";

    assert_eq!(count(text, "Fmt"), 1);
}

#[test]
fn a_parameter_of_an_outer_block_lambda_outlives_an_inner_block() {
    let text = "vim9script\ndef F()\n  Pick((choice) => {\n    Pick((action) => {\n      return action\n    })\n    return choice\n  })\nenddef\n";

    assert_eq!(count(text, "choice"), 0);
    assert_eq!(count(text, "action"), 0);
}

/// A brace a broken line never closes must not bind the name for the
/// rest of the file, where it would cost a project symbol its credit.
#[test]
fn a_block_lambda_left_open_ends_with_the_body_around_it() {
    let text = "vim9script\ndef F()\n  Pick((Fmt) => {\n    return Fmt\nenddef\ndef G()\n  Fmt()\nenddef\n";

    assert_eq!(count(text, "Fmt"), 1);
}

/// A return type stands between the parameter list and the arrow, so
/// the bracket before the arrow is not the one that closes the list.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn a_parameter_of_a_lambda_that_states_a_return_type_is_not_a_reference() {
    let text = "vim9script\ndef F(s: string)\n  echo s->substitute('a', (m: list<string>): string => m[1], 'g')\nenddef\n";

    assert_eq!(count(text, "m"), 0);
}

#[test]
fn a_parameter_of_a_lambda_that_returns_a_container_is_not_a_reference() {
    let text = "vim9script\ndef F(xs: list<string>)\n  echo xs->mapnew((_, text: string): list<any> => [text])\nenddef\n";

    assert_eq!(count(text, "text"), 0);
}

/// Text the `execute` family runs is read for names a second time,
/// after the tokens of its interpolation, and that reading must know
/// the variables of the body as the first one does.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn a_loop_variable_in_executed_text_is_not_a_reference() {
    let text = "vim9script\ndef F(xs: list<string>)\n  for grp in xs\n    execute $'highlight {grp} gui=NONE'\n  endfor\nenddef\n";

    assert_eq!(count(text, "grp"), 0);
}

#[test]
fn a_parameter_in_executed_text_is_not_a_reference() {
    let text = "vim9script\ndef F(amt: number)\n  execute $'resize {amt}'\nenddef\n";

    assert_eq!(count(text, "amt"), 0);
}

/// A loop at script level binds its variable as one in a body does,
/// and declares no symbol for a read of it to reach.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn a_loop_variable_at_script_level_is_not_a_reference() {
    let text = "vim9script\nfor item in ITEMS\n  Register(item)\nendfor\n";

    assert_eq!(count(text, "item"), 0);
    assert_eq!(count(text, "ITEMS"), 1);
}

/// The names in the brackets are declared there, as the one name of a
/// plain `var` is, so the line that declares them reads none of them.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn the_names_an_unpacking_declares_are_not_references_where_declared() {
    let text = "vim9script\ndef F()\n  var [first, last] = Bounds()\nenddef\n";

    assert_eq!(count(text, "first"), 0);
    assert_eq!(count(text, "last"), 0);
    assert_eq!(count(text, "Bounds"), 1);
}

/// FUNCTION: The reference one snippet emits for a name.
fn one(text: &str, name: &str) -> Reference {
    refs(text)
        .into_iter()
        .find(|r| r.name == name)
        .unwrap_or_else(|| panic!("no reference named {name}"))
}

/// A def inside a def reads the variables of the body around it. The
/// inner body's id does not name the outer one, so the scan states
/// the variable the read means.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn a_read_in_a_nested_def_names_the_variable_of_the_body_around_it() {
    let text =
        "vim9script\ndef F()\n  var total = 0\n  def Walk()\n    echo total\n  enddef\nenddef\n";

    assert_eq!(
        one(text, "total").target.map(|id| id.to_string()),
        Some("autoload/p.vim::F.total".to_string())
    );
}

#[test]
fn a_read_two_defs_deep_names_the_variable_of_the_outermost_body() {
    let text = "vim9script\ndef F()\n  var total = 0\n  def A()\n    def B()\n      echo total\n    enddef\n  enddef\nenddef\n";

    assert_eq!(
        one(text, "total").target.map(|id| id.to_string()),
        Some("autoload/p.vim::F.total".to_string())
    );
}

#[test]
fn a_parameter_of_the_body_around_a_nested_def_is_not_a_reference() {
    let text = "vim9script\ndef F(root: string)\n  def Walk()\n    echo root\n  enddef\nenddef\n";

    assert_eq!(count(text, "root"), 0);
}

#[test]
fn a_parameter_read_after_a_nested_def_closes_is_not_a_reference() {
    let text = "vim9script\ndef F(root: string)\n  def Walk()\n  enddef\n  echo root\nenddef\n";

    assert_eq!(count(text, "root"), 0);
}

/// A parameter of the nested def hides the variable around it, so
/// the read is of the parameter and names no variable.
#[test]
fn a_parameter_of_a_nested_def_hides_the_variable_around_it() {
    let text = "vim9script\ndef F()\n  var total = 0\n  def Walk(total: number)\n    echo total\n  enddef\nenddef\n";

    assert_eq!(count(text, "total"), 0);
}

/// A variable the body declares after the nested def is not one the
/// def can read, so a read of that spelling names no variable.
#[test]
fn a_variable_declared_after_a_nested_def_is_not_named_by_it() {
    let text =
        "vim9script\ndef F()\n  def Walk()\n    echo total\n  enddef\n  var total = 0\nenddef\n";

    assert_eq!(one(text, "total").target, None);
}

/// A variable of one body is no variable of the next, so a def that
/// follows names none of it.
#[test]
fn a_variable_of_a_closed_body_is_not_named_by_the_next_body() {
    let text = "vim9script\ndef F()\n  var total = 0\nenddef\ndef G()\n  def Walk()\n    echo total\n  enddef\nenddef\n";

    assert_eq!(one(text, "total").target, None);
}

/// A variadic parameter is a parameter, and its body reads it by name.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/93
#[test]
fn a_variadic_parameter_read_in_its_body_is_no_reference() {
    let text = "vim9script\ndef F(first: number, ...items: list<any>)\n  for i in items\n    echo i first\n  endfor\nenddef\n";

    assert_eq!(count(text, "items"), 0);
}
