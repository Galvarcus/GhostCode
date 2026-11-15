//! A string the `execute` family runs: which of its words are Vim's
//! own, and which keep the credit they carry.
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

/// FUNCTION: The reference one snippet emits for a name, with its mark.
fn one(text: &str, name: &str) -> Reference {
    refs(text)
        .into_iter()
        .find(|r| r.name == name)
        .unwrap_or_else(|| panic!("no reference named {name}"))
}

/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn a_command_in_an_executed_string_is_marked_as_vims() {
    let text = "vim9script\ndef F(p: string)\n  execute 'silent file ' .. p\nenddef\n";

    assert!(one(text, "silent").owned);
    assert!(one(text, "file").owned);
}

#[test]
fn an_abbreviated_execute_reaches_the_same_reading() {
    let text = "vim9script\ndef F(p: string)\n  exe 'silent file ' .. p\nenddef\n";

    assert!(one(text, "silent").owned);
}

/// `win_execute` is deliberately not read. Its strings are
/// interpolated expressions, so harvesting one adds a second copy of
/// every name the lexer already read as code.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn a_string_a_window_runs_is_not_harvested() {
    let text = "vim9script\ndef F(w: number)\n  win_execute(w, 'silent edit x')\nenddef\n";

    assert_eq!(count(text, "silent"), 0);
}

/// Three symbols in the corpora are credited only by text after a
/// gap, so the stop at a gap must not take the harvest with it.
#[test]
fn a_name_after_a_gap_keeps_its_reference() {
    let text =
        "vim9script\ndef F(c: string)\n  execute $'nnoremap <C-w>{c} <ScriptCmd>Resize()<CR>'\nenddef\n";

    assert_eq!(count(text, "Resize"), 1);
    assert!(!one(text, "Resize").owned);
}

#[test]
fn an_option_in_an_executed_string_is_marked_as_vims() {
    let text = "vim9script\ndef F(n: number)\n  execute $'setlocal textwidth={n}'\nenddef\n";

    assert!(one(text, "setlocal").owned);
    assert!(one(text, "textwidth").owned);
}

/// A string in no `execute` position is not a command line. It
/// becomes a text record, which is matched against the project's own
/// names alone.
#[test]
fn a_string_in_no_execute_position_is_untouched() {
    let text = "vim9script\ndef F()\n  echo 'edit the file first'\nenddef\n";

    assert_eq!(count(text, "edit"), 0);
}

/// Only the word that reads a string opens the gate. A variable whose
/// name abbreviates one does not, or a message held in it is read as a
/// call site and the finding it should not touch disappears.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn a_variable_named_like_an_abbreviation_does_not_open_the_gate() {
    let text = "vim9script\ndef F()\n  var ev = 'p#table#Hidden is the name'\n  echo ev\nenddef\n";

    assert_eq!(count(text, "p#table#Hidden"), 0);
}

/// A gap is read twice, as code and as text. The reading as text
/// must not make a bare name of a key, or a function of that
/// spelling is credited by a dictionary that happens to share it.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/71
#[test]
fn a_name_behind_a_dot_in_an_executed_gap_is_a_member() {
    let text = "vim9script\ndef F()\n  var item = {Enabled: 1}\n  execute $'echo {item.Enabled}'\nenddef\n";
    let found: Vec<Reference> = refs(text)
        .into_iter()
        .filter(|r| r.name == "Enabled")
        .collect();

    assert!(!found.is_empty());
    assert!(found.iter().all(|r| r.member), "{found:?}");
}

/// The receiver goes with the name, so that a constant reached
/// through the alias of an import keeps its credit.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/71
#[test]
fn a_name_behind_a_dot_in_an_executed_gap_keeps_its_receiver() {
    let text = "vim9script\nimport autoload 'p/c.vim' as CO\ndef F()\n  execute $'doautocmd User {CO.EVENT}'\nenddef\n";
    let found: Vec<Reference> = refs(text)
        .into_iter()
        .filter(|r| r.name == "EVENT")
        .collect();

    assert!(!found.is_empty());
    assert!(
        found.iter().all(|r| r.recv.as_deref() == Some("CO")),
        "{found:?}"
    );
}

/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/71
#[test]
fn a_called_name_in_the_text_beside_a_key_of_its_spelling_stays_bare() {
    let text = "vim9script\ndef F()\n  var item = {Enabled: 1}\n  execute $'call Enabled() | echo {item.Enabled}'\nenddef\n";

    assert!(refs(text)
        .iter()
        .any(|r| r.name == "Enabled" && !r.member && r.recv.is_none()));
}

/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/125
#[test]
fn a_local_inside_the_gap_of_any_read_string_is_dropped() {
    let text = "vim9script\ndef F(provider: string, sid: number)\n  var o = eval($'{provider}.options')\n  echo o exists($'{provider}.x')\n  echo function($'<SNR>{sid}_{provider}')\nenddef\n";

    assert_eq!(count(text, "provider"), 0);
    assert_eq!(count(text, "sid"), 0);
}

/// The gap may hold the name of an imported script, so the word behind
/// its dot may be a function of that script, and it stays bare.
#[test]
fn a_name_behind_a_dot_after_a_gap_of_an_evaluated_string_stays_bare() {
    let text =
        "vim9script\ndef F(provider: string)\n  echo eval($'{provider}.Completor')\nenddef\n";

    assert!(!one(text, "Completor").member);
}

/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/126
#[test]
fn a_string_after_a_dict_key_named_function_is_text() {
    let text = "vim9script\nconst M = {\n  def: 'E1057: Missing :enddef', function: 'E126: Missing :endfunction',\n}\necho M\n";

    for name in ["E126", "Missing", "endfunction"] {
        assert_eq!(count(text, name), 0, "{name}");
    }
}

#[test]
fn a_string_in_the_brackets_of_function_still_names_a_function() {
    let text = "vim9script\ndef Helper()\nenddef\necho function('Helper')\n";

    assert_eq!(count(text, "Helper"), 1);
}

/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/142
#[test]
fn the_shell_command_of_an_executed_bang_is_vims() {
    let text = "vim9script\ndef Open(url: string)\n  execute '!xdg-open ' .. url\nenddef\n";

    for name in ["xdg", "open"] {
        assert!(
            refs(text)
                .iter()
                .filter(|r| r.name == name)
                .all(|r| r.owned),
            "{name}"
        );
    }
}
