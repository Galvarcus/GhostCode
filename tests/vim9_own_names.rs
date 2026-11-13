//! The names Vim9 owns: which references the scan marks as the
//! language's own rather than as a name this project could declare.
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

/// FUNCTION: Whether the references to a name are the language's own,
/// as a list, so that a snippet naming it twice shows both answers.
fn owned(text: &str, name: &str) -> Vec<bool> {
    refs(text)
        .iter()
        .filter(|r| r.name == name)
        .map(|r| r.owned)
        .collect()
}

#[test]
fn a_type_word_in_an_annotation_is_the_languages_own() {
    let text = "vim9script\ndef F()\n  var s: string\nenddef\n";

    assert_eq!(owned(text, "string"), vec![true]);
}

#[test]
fn a_return_type_is_the_languages_own() {
    let text = "vim9script\ndef F(): bool\n  return true\nenddef\n";

    assert_eq!(owned(text, "bool"), vec![true]);
}

#[test]
fn a_type_word_inside_another_type_is_the_languages_own() {
    let text = "vim9script\ndef F()\n  var l: list<dict<string>>\nenddef\n";

    assert_eq!(owned(text, "list"), vec![true]);
    assert_eq!(owned(text, "dict"), vec![true]);
    assert_eq!(owned(text, "string"), vec![true]);
}

/// `string` is the one name that is both a type word and a function
/// Vim defines. Called, it is Vim's function, and Vim's own names are
/// dropped rather than marked, so the reference list holds nothing for
/// it. In an annotation it is the type word above.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn a_type_word_that_is_called_is_vims_own_function() {
    let text = "vim9script\ndef F()\n  var s = string(1)\nenddef\n";

    assert!(owned(text, "string").is_empty());
}

#[test]
fn an_annotation_naming_a_class_is_a_reference_like_any_other() {
    let text = "vim9script\ndef F()\n  var m: Menu\nenddef\n";

    assert_eq!(
        owned(text, "Menu"),
        vec![false],
        "a project class must still be credited by the annotation naming it"
    );
}

#[test]
fn a_null_literal_is_the_languages_own() {
    let text = "vim9script\ndef F(): any\n  return null_object\nenddef\n";

    assert_eq!(owned(text, "null_object"), vec![true]);
}

/// An enum value may carry a reserved name, so a null literal is
/// marked rather than dropped: a reference the scan never emits
/// credits nothing, and the value would be reported as unreferenced.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn a_null_literal_is_still_a_reference() {
    let text = "vim9script\ndef F(): any\n  return null_object\nenddef\n";

    assert_eq!(
        refs(text)
            .iter()
            .filter(|r| r.name == "null_object")
            .count(),
        1
    );
}

#[test]
fn an_object_type_is_the_languages_own() {
    let text = "vim9script\ndef F()\n  var c: object<C>\nenddef\n";

    assert_eq!(owned(text, "object"), vec![true]);
}

/// The type of a parameter reached past the tokens a signature can
/// hold: `...` for a variadic argument and `?` for an optional one.
#[test]
fn a_type_inside_a_func_type_is_the_languages_own() {
    let text = "vim9script\ndef F()\n  var f: func(...list<blob>): void\n  var g: func(number, ?channel): bool\nenddef\n";

    assert_eq!(owned(text, "blob"), vec![true]);
    assert_eq!(owned(text, "channel"), vec![true]);
}

/// A dictionary entry whose value is a call: the value is a use of
/// the name it calls, whatever the colon before it suggests.
#[test]
fn a_call_after_a_colon_is_a_reference_like_any_other() {
    let text = "vim9script\ndef F()\n  var d = {days: Width(30)}\nenddef\n";

    assert_eq!(owned(text, "Width"), vec![false]);
}

/// Vim9 compares identity with a word rather than a sign, and the
/// word is the language's as surely as `in` is. Six forms exist. The
/// `#` and the bare form each need naming, because the lexer lets a
/// name hold a `#` so that `plugin#Func` stays whole; the `?` form
/// does not, because its mark is punctuation.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn an_identity_operator_is_not_a_reference() {
    let text = "vim9script\ndef F(a: any, b: any)\n  if a is b\n    echo 1\n  endif\nenddef\n";

    assert_eq!(count(text, "is"), 0);
}

#[test]
fn a_negated_identity_operator_is_not_a_reference() {
    let text = "vim9script\ndef F(a: any, b: any)\n  if a isnot b\n    echo 1\n  endif\nenddef\n";

    assert_eq!(count(text, "isnot"), 0);
}

#[test]
fn a_cased_identity_operator_is_not_a_reference() {
    let text = "vim9script\ndef F(a: any, b: any)\n  if a is# b\n    echo 1\n  endif\nenddef\n";

    assert_eq!(count(text, "is#"), 0);
}

#[test]
fn a_cased_negated_identity_operator_is_not_a_reference() {
    let text = "vim9script\ndef F(a: any, b: any)\n  if a isnot# b\n    echo 1\n  endif\nenddef\n";

    assert_eq!(count(text, "isnot#"), 0);
}

/// The match is the whole name. Every script of the project opens by
/// reading `is_loaded`, which an operator must not take with it.
#[test]
fn a_name_that_opens_with_an_operator_is_still_a_reference() {
    let text = "vim9script\nvar is_loaded = true\necho is_loaded\n";

    assert_eq!(count(text, "is_loaded"), 1);
}

/// `KEYWORDS` holds the words Vim9 has, not the words the report
/// prints. `enum_value` is the kind word for a value of an enum, and
/// a project may spell a variable that way.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/28
#[test]
fn a_name_the_report_prints_is_still_a_reference() {
    let text = "vim9script\nvar enum_value = 1\necho enum_value\n";

    assert_eq!(count(text, "enum_value"), 1);
}

/// Vim9 once wrote `import {Foo} from 'x.vim'` and no longer does:
/// Vim 9.2 answers that form with E720. The word is an ordinary name
/// now, and a plausible one for a range or a sender.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/28
#[test]
fn a_word_vim9_no_longer_has_is_still_a_reference() {
    let text = "vim9script\nvar from = 1\necho from\n";

    assert_eq!(count(text, "from"), 1);
}

/// A Vim9 declaration cannot open with a sigil, so a name that does
/// is Vim's own: `&` an option, `$` an environment variable, `@` a
/// register. No table is needed to tell them apart from a project's
/// names, because no project name can look like one.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn an_option_is_not_a_reference() {
    let text = "vim9script\nif &cp\n  finish\nendif\n";

    assert_eq!(count(text, "&cp"), 0);
}

#[test]
fn an_environment_variable_is_not_a_reference() {
    let text = "vim9script\ndef F()\n  echo $HOME\nenddef\n";

    assert_eq!(count(text, "$HOME"), 0);
}

#[test]
fn a_register_is_not_a_reference() {
    let text = "vim9script\ndef F()\n  echo @a\nenddef\n";

    assert_eq!(count(text, "@a"), 0);
}

/// `&l:wrap` is three tokens, because the lexer ends a name at a
/// colon, so the option word after the sigil is Vim's as well.
#[test]
fn a_scoped_option_is_not_a_reference() {
    let text = "vim9script\ndef F()\n  echo &l:wrap\nenddef\n";

    assert_eq!(count(text, "&l"), 0);
    assert_eq!(count(text, "wrap"), 0);
}

/// Vim's key notation stands inside angle brackets on a mapping
/// statement, and none of it is a name the project could declare.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn a_mapping_argument_is_not_a_reference() {
    let text = "vim9script\nnnoremap <buffer> <nowait> q <ScriptCmd>Close()<CR>\n";

    assert_eq!(count(text, "buffer"), 0);
    assert_eq!(count(text, "nowait"), 0);
}

#[test]
fn the_parts_of_a_key_name_are_not_references() {
    let text = "vim9script\nnnoremap <C-x> <ScriptCmd>Close()<CR>\n";

    assert_eq!(count(text, "C"), 0);
    assert_eq!(count(text, "ScriptCmd"), 0);
    assert_eq!(count(text, "CR"), 0);
}

/// The whole point of a mapping is what it runs, and that name sits
/// outside the brackets, where nothing may touch it.
#[test]
fn the_function_a_mapping_runs_is_still_a_reference() {
    let text = "vim9script\nnnoremap <buffer> q <ScriptCmd>Close()<CR>\n";

    assert_eq!(count(text, "Close"), 1);
}

/// The rule is anchored to a mapping statement, so a generic type is
/// left to the type words, which mark rather than drop.
#[test]
fn a_generic_type_is_left_to_the_type_words() {
    let text = "vim9script\ndef F()\n  var l: list<string>\nenddef\n";

    assert_eq!(owned(text, "string"), vec![true]);
}

#[test]
fn a_notation_word_outside_a_mapping_is_still_a_reference() {
    let text = "vim9script\ndef F()\n  echo buffer\nenddef\n";

    assert_eq!(count(text, "buffer"), 1);
}

/// An `<expr>` mapping's right side is an expression, and a
/// comparison in one wears the same bracket the notation does. A span
/// that never closes is a comparison, not notation.
#[test]
fn a_comparison_in_a_mapping_expression_is_still_a_reference() {
    let text = "vim9script\ncnoremap <expr> q Low < High ? 'a' : 'b'\n";

    assert_eq!(count(text, "High"), 1);
}

/// `:augroup` takes the name of an autocommand group and nothing
/// else, and a group lives in Vim's namespace rather than the
/// project's.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn an_autocommand_group_is_not_a_reference() {
    let text = "vim9script\naugroup END\n";

    assert_eq!(count(text, "END"), 0);
}

#[test]
fn a_group_the_project_names_is_not_a_reference() {
    let text = "vim9script\naugroup bartleby_save\naugroup END\n";

    assert_eq!(count(text, "bartleby_save"), 0);
}

#[test]
fn an_autocommand_flag_is_not_a_reference() {
    let text = "vim9script\nautocmd BufEnter * ++once Refresh()\n";

    assert_eq!(count(text, "once"), 0);
}

#[test]
fn a_pattern_argument_of_an_autocommand_is_not_a_reference() {
    let text = "vim9script\nautocmd BufEnter <buffer> Refresh()\n";

    assert_eq!(count(text, "buffer"), 0);
}

/// What an autocommand runs is the reason it exists, and that name
/// stands outside every part of the syntax around it.
#[test]
fn the_command_an_autocommand_runs_is_still_a_reference() {
    let text = "vim9script\nautocmd BufEnter <buffer> ++once Refresh()\n";

    assert_eq!(count(text, "Refresh"), 1);
}

/// The two words a class line states its parents with are Vim9's own,
/// and the name after each is the reference.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn the_word_before_an_interface_a_class_implements_is_not_a_reference() {
    let text = "vim9script\ninterface Shape\nendinterface\nclass Box implements Shape\nendclass\n";

    assert_eq!(count(text, "implements"), 0);
    assert_eq!(count(text, "Shape"), 1);
}

#[test]
fn the_word_before_a_class_another_extends_is_not_a_reference() {
    let text = "vim9script\nclass Base\nendclass\nclass Box extends Base\nendclass\n";

    assert_eq!(count(text, "extends"), 0);
    assert_eq!(count(text, "Base"), 1);
}

/// A class stands in a list of types as a builtin type does, so a
/// type word behind one is still a type.
#[test]
fn a_type_word_behind_a_class_in_a_func_type_is_marked_as_vims() {
    let text = "vim9script\ndef F(Visit: func(BI.Item, list<BI.Item>)): void\nenddef\n";

    assert!(refs(text)
        .iter()
        .filter(|r| r.name == "list")
        .all(|r| r.owned));
}

/// A value behind a comma in a call is no type, whatever stands
/// before the comma.
#[test]
fn a_value_behind_a_class_in_a_call_is_not_marked() {
    let text = "vim9script\ndef F()\n  Run(Item, list)\nenddef\n";

    assert!(refs(text)
        .iter()
        .filter(|r| r.name == "list")
        .all(|r| !r.owned));
}
