//! A string the `execute` family runs, read as the command line Vim
//! will run: which of its words are Vim's own, and where the reading
//! has to stop.
//!
//! License: GNU GPL 3.0

use std::collections::HashSet;

use super::excmds;
use super::lex;
use super::lex::TokKind;
use super::parse;
use super::parse::identifiers;

/// What opens the interpolated part of a string, which is where the
/// text stops being known: `$'setlocal tw={x}'` is read to the brace
/// and no further.
const GAP: char = '{';

/// FUNCTION: Every name the argument holds, in order, each with
/// whether it is Vim's own word.
///
/// The reading stops at the first gap, because a word after one stands
/// at a position no one can know: in
/// `execute 'silent ' .. mods .. ' edit '`, whether `edit` is a
/// command depends on what `mods` left behind. The harvest does not
/// stop there. Three symbols in the corpora are credited only by text
/// after a gap, so every name still comes back; the ones past the gap
/// simply come back unmarked.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
pub fn names(arg: &str) -> Vec<(String, bool)> {
    let (head, tail) = arg.split_once(GAP).unwrap_or((arg, ""));
    let vims = vims_words(head);

    let mut out: Vec<(String, bool)> = identifiers(head)
        .into_iter()
        .map(|name| (name.clone(), vims.contains(&name)))
        .collect();

    out.extend(identifiers(tail).into_iter().map(|name| (name, false)));
    out
}

/// FUNCTION: The words of a readable head that Vim reads as its own: a
/// command at a head position, a modifier before one, and the
/// arguments of a set-family command and of a command whose
/// arguments are Vim's own text, such as `:highlight`.
///
/// The head is lexed and run through the statement rules, so a
/// command written short is read as one and a bar starts the next
/// command, exactly as in code.
fn vims_words(head: &str) -> HashSet<String> {
    let mut out = HashSet::new();

    for stmt in parse::statements(&lex::tokens(head)) {
        let heads = parse::heads(&stmt);

        for (i, tok) in stmt.iter().enumerate() {
            if tok.kind != TokKind::Ident {
                continue;
            }

            let vims = (parse::in_command(&stmt, i, &heads)
                && excmds::canonical(&tok.text).is_some())
                || parse::set_args(&stmt, i, &heads)
                || parse::text_args(&stmt, i, &heads);

            if vims {
                out.insert(tok.text.clone());
            }
        }
    }

    out
}

#[cfg(test)]
mod tests {
    use super::names;

    /// FUNCTION: The names of an argument that are Vim's own word.
    fn words_of(arg: &str) -> Vec<String> {
        names(arg)
            .into_iter()
            .filter(|(_, vims)| *vims)
            .map(|(name, _)| name)
            .collect()
    }

    #[test]
    fn a_command_at_the_head_is_vims() {
        assert_eq!(words_of("silent file x"), vec!["silent", "file"]);
    }

    #[test]
    fn an_abbreviated_command_at_the_head_is_vims() {
        assert_eq!(words_of("sil! bwipe! 3"), vec!["sil", "bwipe"]);
    }

    #[test]
    fn every_name_of_the_argument_comes_back_in_order() {
        assert_eq!(
            names("silent file x"),
            vec![
                ("silent".to_string(), true),
                ("file".to_string(), true),
                ("x".to_string(), false),
            ]
        );
    }

    #[test]
    fn the_head_ends_at_the_first_gap() {
        assert_eq!(words_of("setlocal tw={x} edit"), vec!["setlocal", "tw"]);
    }

    #[test]
    fn every_command_of_a_literal_string_is_read() {
        assert_eq!(
            words_of("silent! bwipe! | edit x"),
            vec!["silent", "bwipe", "edit"]
        );
    }

    #[test]
    fn an_argument_that_is_no_command_is_left_alone() {
        assert_eq!(words_of("edit Foo"), vec!["edit"]);
    }

    #[test]
    fn the_arguments_of_a_highlight_command_are_vims() {
        assert_eq!(
            words_of("highlight link Foo Normal"),
            vec!["highlight", "link", "Foo", "Normal"]
        );
    }

    #[test]
    fn a_name_after_a_gap_is_never_vims() {
        assert_eq!(words_of("{x} edit"), Vec::<String>::new());
    }
}
