//! Vim's highlighting: the words after a `:highlight` or a `:syntax`
//! command, which are Vim's own text from the command to its end.
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
    Vim9.scan(&source("syntax/p.vim", text), &mut found)
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

/// A group, the group it links to, and the words between them are
/// names Vim keeps, and nothing the project declares can be meant by
/// one. They are marked rather than dropped, so a symbol of the same
/// spelling keeps the credit it had.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn a_group_after_a_highlight_command_is_marked_as_vims() {
    let text = "vim9script\nhighlight default link pluginTitle Title\n";

    for name in ["default", "link", "pluginTitle", "Title"] {
        assert!(one(text, name).owned, "{name}");
    }
}

#[test]
fn an_attribute_of_a_highlight_command_is_marked_as_vims() {
    let text = "vim9script\nhighlight PluginDim ctermfg=8 guifg=Grey\n";

    for name in ["PluginDim", "ctermfg", "guifg", "Grey"] {
        assert!(one(text, name).owned, "{name}");
    }
}

#[test]
fn an_abbreviated_highlight_command_claims_its_arguments() {
    let text = "vim9script\nhi link pluginTitle Title\n";

    assert!(one(text, "pluginTitle").owned);
}

#[test]
fn a_group_after_a_syntax_command_is_marked_as_vims() {
    let text =
        "vim9script\nsyntax region pluginNote start=/x/ end=/y/ contains=pluginKey keepend\n";

    for name in [
        "region",
        "pluginNote",
        "start",
        "contains",
        "pluginKey",
        "keepend",
    ] {
        assert!(one(text, name).owned, "{name}");
    }
}

/// A pattern writes its alternation as an escaped bar, which ends no
/// command, so the words behind one are still the pattern's.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn a_word_of_a_syntax_pattern_behind_an_escaped_bar_is_marked_as_vims() {
    let text = "vim9script\nsyntax match pluginFade /^\\c\\(fade\\|black\\)$/ contained\n";

    for name in ["fade", "black", "contained"] {
        assert!(one(text, name).owned, "{name}");
    }
}

#[test]
fn a_highlight_command_claims_nothing_past_a_bar() {
    let text = "vim9script\ndef F()\n  highlight clear | Fn()\nenddef\n";

    assert!(one(text, "clear").owned);
    assert!(!one(text, "Fn").owned);
}

/// The claim begins at the command, not at the head of the statement,
/// so a call before one keeps its credit.
#[test]
fn a_word_before_a_syntax_command_is_not_its_argument() {
    let text = "vim9script\ndef F()\n  Fn() | syntax clear\nenddef\n";

    assert!(!one(text, "Fn").owned);
    assert!(one(text, "clear").owned);
}

/// The claim begins only where Vim reads a command. `syntax` is a name
/// Vim9 accepts for a variable, and an assigned one is no command.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn a_variable_named_after_a_syntax_command_claims_nothing() {
    let text = "vim9script\ndef F()\n  var syntax: dict<bool> = {}\n  syntax['a'] = Fn()\nenddef\n";

    assert!(!one(text, "Fn").owned);
}

/// Text the `execute` family runs is read as the command line it is,
/// so a highlight command written there claims the same words.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn a_highlight_command_in_executed_text_is_marked_as_vims() {
    let text = "vim9script\ndef F()\n  execute 'highlight link pluginTitle Title'\nenddef\n";

    assert!(one(text, "pluginTitle").owned);
}

/// The words after `=<<` are the heredoc's own syntax, `trim`, `eval`
/// and the end marker, and never a name.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/89
#[test]
fn the_words_that_open_a_heredoc_are_no_references() {
    let text = "vim9script\nvar lines =<< trim END\n  hello\nEND\nvar more =<< trim eval DATA\n  x\nDATA\n";
    let names: Vec<String> = refs(text).into_iter().map(|r| r.name).collect();

    for word in ["trim", "eval", "END", "DATA"] {
        assert!(!names.iter().any(|n| n == word), "{word}: {names:?}");
    }
}

/// The value before `=<<` is still read.
#[test]
fn the_target_of_a_heredoc_assignment_is_still_read() {
    let text = "vim9script\nvar lines: list<string> = []\nlines =<< trim END\n  hello\nEND\n";

    assert_eq!(refs(text).iter().filter(|r| r.name == "lines").count(), 1);
}

/// A key of a dictionary may share the name of a word that opens a
/// block, and the colon against it says it is a key.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/116
#[test]
fn a_dict_key_named_as_a_block_word_keeps_its_dict_whole() {
    for key in ["command", "autocmd", "if", "return"] {
        let text = format!(
            "vim9script\nvar d = {{\n  title: 1,\n  {key}: 2,\n  other_key: 3,\n}}\necho d\n"
        );
        let names: Vec<String> = refs(&text).into_iter().map(|r| r.name).collect();

        assert!(!names.iter().any(|n| n == "other_key"), "{key}: {names:?}");
    }
}

/// A block word inside a block lambda starts a statement of its own,
/// and the brace that closes the lambda returns to the dict or the call
/// around it, whose keys are keys again.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/96
#[test]
fn a_dict_key_after_a_block_lambda_with_an_if_is_a_key() {
    let text = "vim9script\nvar o = {\n  out_cb: (ch, msg) => {\n    if msg == \"\"\n      echo 1\n    endif\n  },\n  err_msg: 0,\n}\necho o\n";
    let names: Vec<String> = refs(text).into_iter().map(|r| r.name).collect();

    assert!(!names.iter().any(|n| n == "err_msg"), "{names:?}");
}

#[test]
fn a_dict_argument_after_a_block_lambda_with_an_if_is_a_dict() {
    let text = "vim9script\nvar t = timer_start(20, (_) => {\n  if 1\n    echo 1\n  endif\n}, {repeat: 0})\n";
    let names: Vec<String> = refs(text).into_iter().map(|r| r.name).collect();

    assert!(!names.iter().any(|n| n == "repeat"), "{names:?}");
}

/// Vim9 requires a space after the colon of a key, so a name glued to
/// `v:` is a variable of Vim's, inside a dict as well.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/97
#[test]
fn a_v_variable_after_a_dict_key_is_no_reference() {
    let text = "vim9script\nvar d = {id: 1, error: {code: 2,\n  message: v:exception}}\nvar e = {message: v:progpath}\necho d e\n";
    let names: Vec<String> = refs(text).into_iter().map(|r| r.name).collect();

    assert!(
        !names.iter().any(|n| n == "exception" || n == "progpath"),
        "{names:?}"
    );
}
