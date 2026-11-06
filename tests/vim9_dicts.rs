//! A member access on a dict: the word after the dot is a key, not a
//! symbol, and telling the two apart rests on the receiver's type.
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

/// A parameter states the type, so the key is known for what it is.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn a_key_of_a_dict_parameter_is_not_a_reference() {
    let text = "vim9script\ndef F(ctx: dict<any>)\n  echo ctx.row\nenddef\n";

    assert_eq!(count(text, "row"), 0);
}

#[test]
fn a_key_of_a_declared_dict_is_not_a_reference() {
    let text = "vim9script\ndef F()\n  var ctx: dict<any> = Get()\n  echo ctx.row\nenddef\n";

    assert_eq!(count(text, "row"), 0);
}

/// A dict declared at script level is a symbol of the project, and
/// its keys are still keys.
#[test]
fn a_key_of_a_script_level_dict_is_not_a_reference() {
    let text = "vim9script\nvar ctx: dict<any> = Get()\necho ctx.row\n";

    assert_eq!(count(text, "row"), 0);
}

/// The dict itself is a name the project declared, and the access is
/// a read of it, which is the credit that keeps it off the report.
#[test]
fn the_dict_a_key_is_read_from_is_still_a_reference() {
    let text = "vim9script\nvar ctx: dict<any> = Get()\necho ctx.row\n";

    assert_eq!(count(text, "ctx"), 1);
}

/// The type inside the brackets changes nothing: the outermost type
/// is what decides.
#[test]
fn a_key_of_a_nested_dict_type_is_not_a_reference() {
    let text = "vim9script\ndef F(ctx: dict<list<string>>)\n  echo ctx.rows\nenddef\n";

    assert_eq!(count(text, "rows"), 0);
}

/// A field of the class may hold a dict, and `types.field` knows its
/// type, so the key after it is a key.
#[test]
fn a_key_of_a_dict_field_is_not_a_reference() {
    let text = "vim9script\nclass C\n  var opts: dict<any>\n  def Run()\n    echo this.opts.width\n  enddef\nendclass\n";

    assert_eq!(count(text, "width"), 0);
}

/// `any` is not a dict. It is the receiver whose type is genuinely
/// unknown, where every candidate member must still take the credit,
/// or a field reached only through one is reported.
#[test]
fn a_member_of_an_untyped_receiver_is_still_a_reference() {
    let text = "vim9script\ndef F(thing: any): string\n  return thing.label\nenddef\n";

    assert_eq!(count(text, "label"), 1);
}

#[test]
fn a_method_of_a_class_is_still_a_reference() {
    let text = "vim9script\ndef F(m: Menu)\n  m.Open()\nenddef\n";

    assert_eq!(count(text, "Open"), 1);
}

/// The second hop is not a key. `ctx.row` is a key, and whatever it
/// holds has no type the parser knows, so `item` is a member of an
/// unknown receiver and keeps its credit.
#[test]
fn the_hop_after_a_key_is_still_a_reference() {
    let text = "vim9script\ndef F(ctx: dict<any>)\n  echo ctx.row.item\nenddef\n";

    assert_eq!(count(text, "row"), 0);
    assert_eq!(count(text, "item"), 1);
}

/// A dict of funcrefs costs nothing, because the funcref was credited
/// where it was put into the dict, not where the key is read.
#[test]
fn a_funcref_in_a_dict_is_credited_where_it_is_stored() {
    let text =
        "vim9script\ndef F()\n  var acts: dict<func> = {open: OnOpen}\n  acts.open()\nenddef\n";

    assert_eq!(count(text, "OnOpen"), 1);
    assert_eq!(count(text, "open"), 0);
}
