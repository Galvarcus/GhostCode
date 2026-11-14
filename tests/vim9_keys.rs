//! Vim's keys: the left side of a mapping, a right side that is keys
//! and no command, and the arguments of `:normal` and `:emenu`.
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

/// FUNCTION: The reference one snippet emits for a name, with its mark.
fn one(text: &str, name: &str) -> Reference {
    refs(text)
        .into_iter()
        .find(|r| r.name == name)
        .unwrap_or_else(|| panic!("no reference named {name}"))
}

/// The left side of a mapping is the keys the user presses, and the
/// project declares nothing a key could mean. What the mapping runs
/// stands on the right, and that name is left alone.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn the_left_side_of_a_mapping_is_marked_as_vims() {
    let text = "vim9script\nnnoremap <buffer> <silent> dd <ScriptCmd>Delete()<CR>\n";

    assert!(one(text, "dd").owned);
    assert!(!one(text, "Delete").owned);
}

#[test]
fn a_right_side_of_keys_is_marked_as_vims() {
    let text = "vim9script\nxnoremap <buffer> <silent> j gj\n";

    assert!(one(text, "j").owned);
    assert!(one(text, "gj").owned);
}

#[test]
fn a_key_between_two_key_names_is_marked_as_vims() {
    let text = "vim9script\ninoremap <buffer> <C-w> <C-g>u<C-w>\n";

    assert!(one(text, "u").owned);
}

/// A command of Vim's own is what many mappings run, and it stands
/// where a function of the project would.
#[test]
fn a_command_of_vims_that_a_mapping_runs_is_marked_as_vims() {
    let text = "vim9script\nnnoremap <buffer> q <ScriptCmd>close<CR>\n";

    assert!(one(text, "q").owned);
    assert!(one(text, "close").owned);
}

#[test]
fn a_function_a_mapping_calls_from_the_command_line_is_not_marked() {
    let text = "vim9script\nnnoremap <buffer> q :call Fn()<CR>\n";

    assert!(!one(text, "Fn").owned);
}

/// The right side of an `<expr>` mapping is an expression, and every
/// name in one may be the project's.
#[test]
fn the_right_side_of_an_expression_mapping_is_not_marked() {
    let text = "vim9script\ncnoremap <expr> q Low < High ? 'a' : 'b'\n";

    assert!(one(text, "q").owned);
    assert!(!one(text, "Low").owned);
    assert!(!one(text, "High").owned);
}

#[test]
fn the_keys_an_unmapping_names_are_marked_as_vims() {
    let text = "vim9script\ndef F()\n  silent! nunmap <buffer> j\nenddef\n";

    assert!(one(text, "j").owned);
}

/// The claim begins only where Vim reads a command. `nmap` is a name
/// Vim9 accepts for a variable, and an assigned one is no command.
#[test]
fn a_variable_named_after_a_mapping_command_claims_nothing() {
    let text = "vim9script\ndef F()\n  var nmap = Left\n  nmap = Other\nenddef\n";

    assert!(!one(text, "Other").owned);
}

/// `:normal` runs its argument as keys, to the end of the line.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn the_keys_a_normal_command_runs_are_marked_as_vims() {
    let text = "vim9script\ndef F()\n  normal! A more words\nenddef\n";

    for name in ["A", "more", "words"] {
        assert!(one(text, name).owned, "{name}");
    }
}

#[test]
fn a_variable_named_after_the_normal_command_claims_nothing() {
    let text = "vim9script\ndef F()\n  var normal = Left\n  normal = Other\nenddef\n";

    assert!(!one(text, "Other").owned);
}

/// `:emenu` names a menu by its path, and every part of the path is a
/// name Vim keeps, the parts behind a dot as much as the first.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn the_path_an_emenu_command_names_is_marked_as_vims() {
    let text = "vim9script\ndef F()\n  emenu PluginMenu.Sub.Deep\nenddef\n";

    for name in ["PluginMenu", "Sub", "Deep"] {
        assert!(one(text, name).owned, "{name}");
    }
}

/// A `#` behind a space is a key in a mapping, and no comment: a
/// mapping command takes no comment at all. What stands behind the key
/// is still read, so the function the mapping calls is called.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/52
#[test]
fn a_hash_a_mapping_maps_hides_no_call() {
    let text = "vim9script\ninoremap <buffer> # #<ScriptCmd>Heads()<CR>\n";

    assert!(!one(text, "Heads").owned);
}

#[test]
fn a_hash_a_mapping_maps_behind_a_modifier_hides_no_call() {
    let text = "vim9script\nsilent! inoremap <buffer> # #<ScriptCmd>Heads()<CR>\n";

    assert!(!one(text, "Heads").owned);
}

/// An autocommand runs a command behind its pattern, and a mapping
/// there reads its keys as one at the head of a line does.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/52
#[test]
fn a_hash_a_mapping_in_an_autocommand_maps_hides_no_call() {
    let text =
        "vim9script\nautocmd FileType markdown inoremap <buffer> # #<ScriptCmd>Heads()<CR>\n";

    assert!(!one(text, "Heads").owned);
}

#[test]
fn a_hash_on_a_line_that_continues_a_mapping_hides_no_call() {
    let text = "vim9script\ninoremap <buffer> #\n      \\ #<ScriptCmd>Heads()<CR>\n";

    assert!(!one(text, "Heads").owned);
}

/// A bar ends a mapping, and the command behind it takes a comment
/// again.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/52
#[test]
fn a_hash_behind_the_bar_that_ends_a_mapping_is_a_comment() {
    let text = "vim9script\nnnoremap <buffer> x y | echo 1 # Hidden()\n";

    assert!(refs(text).iter().all(|r| r.name != "Hidden"));
}

#[test]
fn a_hash_behind_a_variable_named_after_a_mapping_command_is_a_comment() {
    let text = "vim9script\ndef F()\n  var nmap = 1\n  nmap = 2 # Hidden()\nenddef\n";

    assert!(refs(text).iter().all(|r| r.name != "Hidden"));
}

/// A bracket a mapping maps opens nothing, so the line behind the
/// mapping is a statement of its own and its command stands at a head.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/52
#[test]
fn a_bracket_a_mapping_maps_joins_no_line_to_it() {
    let text = "vim9script\ninoremap <buffer> [ [<ScriptCmd>Titles()<CR>\ninoremap <buffer> x y\n";

    assert!(refs(text)
        .iter()
        .filter(|r| r.name == "inoremap")
        .all(|r| r.owned));
    assert!(!one(text, "Titles").owned);
}

/// A bracket behind a space is a key, where a bracket against the
/// word would index a variable.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/52
#[test]
fn a_bracket_as_the_left_side_of_a_mapping_is_a_key() {
    let text = "vim9script\nnnoremap [ dd\n";

    assert!(one(text, "dd").owned);
}

/// A mapping command stands apart from its arguments, so a word with
/// a colon against it is the key of a dictionary, and the bracket on
/// its line closes what the line above opened.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/52
#[test]
fn a_dictionary_key_named_after_a_mapping_command_is_no_mapping() {
    let text = "vim9script\nvar d = {\n  map: [1],\n  unmap: 2}\nnnoremap <buffer> x y\n";

    assert!(refs(text)
        .iter()
        .filter(|r| r.name == "nnoremap")
        .all(|r| r.owned));
    assert!(one(text, "x").owned);
}

#[test]
fn a_mapping_command_with_its_argument_against_it_is_a_mapping() {
    let text = "vim9script\ninoremap<buffer> # #<ScriptCmd>Heads()<CR>\n";

    assert!(!one(text, "Heads").owned);
}

/// The special arguments of a mapping may stand together with no space.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/91
#[test]
fn the_left_side_after_joined_special_arguments_is_marked_as_vims() {
    let text = "vim9script\nnnoremap <buffer><nowait> g, <ScriptCmd>echo 1<cr>\n";

    assert!(one(text, "g").owned);
}

#[test]
fn the_name_of_a_plug_mapping_is_marked_as_vims() {
    let text = "vim9script\nnmap <c-g> <Plug>(MyToggle)\ninoremap <silent><expr> <Plug>(my-undo-action) Undo()\n";

    for word in ["MyToggle", "my", "undo", "action"] {
        assert!(one(text, word).owned, "{word}");
    }
}

#[test]
fn a_command_behind_the_colon_of_a_right_side_is_marked_as_vims() {
    let text = "vim9script\n:nnoremap <silent> q :quit<CR>\n";

    assert!(one(text, "quit").owned);
}

#[test]
fn the_keys_after_the_end_of_a_command_line_are_marked_as_vims() {
    let text = "vim9script\nnnoremap <buffer> x <ScriptCmd>Toggle()<cr>j\n";

    assert!(one(text, "j").owned);
    assert!(!one(text, "Toggle").owned);
}
