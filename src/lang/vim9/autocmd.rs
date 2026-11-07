//! The autocommand line, read part by part: which words are Vim's own
//! and where the command it runs begins.
//!
//! License: GNU GPL 3.0

use super::events;
use super::excmds;
use std::ops::Range;

use super::lex::Tok;
use super::lex::TokKind;

/// The commands that take an event and, for the first of them, a body.
const COMMANDS: &[&str] = &["autocmd", "doautocmd", "doautoall"];

/// The one that defines rather than fires, and so carries a body.
const DEFINES: &str = "autocmd";

/// What Vim writes where an event name could stand to mean every
/// event, in the forms that remove rather than define.
const EVERY: &str = "*";

/// What opens a flag, as `++once` and `++nested`, which the lexer
/// splits into two of these and a word.
const FLAG: &str = "+";

/// What opens Vim's angle-bracket notation, as `<nomodeline>` and
/// `<buffer>`.
const NOTATION: &str = "<";

/// What separates one event from the next inside a list.
const COMMA: &str = ",";

/// What Vim writes between two commands on one line, which the lexer
/// keeps inside the statement the first of them opened.
const BAR: &str = "|";

/// FUNCTION: The indices an autocommand line owns: everything past
/// the command word up to the command it runs, or up to the end of
/// the statement when it runs none.
///
/// Those are the group, the event list, the pattern, the flags and the
/// name of a `User` event, which stands in the pattern's place. The
/// command word itself is answered by the head rule, which reads the
/// generated table, so this starts past it. `None` for a statement
/// that is no autocommand, which is what keeps `auto = Helper()` from
/// losing the call it carries.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
pub fn owned(stmt: &[Tok], at: usize) -> Option<Range<usize>> {
    line(stmt, at)?;

    // A bar ends the command as surely as the statement does, so a
    // form that runs nothing owns only the words before one: the
    // `Fn()` of `autocmd! * <buffer> | Fn()` is the project's.
    let bar = stmt
        .iter()
        .enumerate()
        .skip(at)
        .find(|(_, tok)| tok.text == BAR)
        .map(|(i, _)| i);

    let end = body(stmt, at).or(bar).unwrap_or(stmt.len()).min(stmt.len());

    Some(at + 1..end)
}

/// FUNCTION: Where the command an autocommand runs begins, and `None`
/// for a statement that is no autocommand or that carries no command:
/// `:doautocmd` fires an event and never runs one, and `:autocmd!`
/// may remove without adding.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
pub fn body(stmt: &[Tok], at: usize) -> Option<usize> {
    let (command, words) = line(stmt, at)?;

    if command != DEFINES {
        return None;
    }

    let mut rest = after_event(stmt, &words)?;

    // The pattern stands between the event list and the command, and
    // the flags stand between the pattern and the command.
    rest.next()?;
    rest.find(|at| !is_flag(stmt, *at))
}

/// FUNCTION: The canonical command of an autocommand statement, with
/// the index at which each of its words begins past the command, and
/// `None` for a statement that is no autocommand.
///
/// `at` is where the statement's command word stands, past any
/// modifier, so `silent doautocmd User Save` reads like the bare form.
/// A head Vim does not read as a command is no autocommand however it
/// is spelled: `auto` abbreviates `autocmd`, and `auto = Helper()`
/// assigns.
fn line(stmt: &[Tok], at: usize) -> Option<(&'static str, Vec<usize>)> {
    if !super::parse::reads_command(stmt, at) {
        return None;
    }

    let command = excmds::canonical(&stmt.get(at)?.text)?;

    if !COMMANDS.contains(&command) {
        return None;
    }

    Some((command, words(stmt, at)))
}

/// FUNCTION: Where each word of a statement begins. A word is a run of
/// tokens no space divides, so `*.fountain` is one and `++once` is
/// one.
fn words(stmt: &[Tok], from: usize) -> Vec<usize> {
    stmt.iter()
        .enumerate()
        .skip(from)
        .filter(|(at, tok)| {
            tok.kind != TokKind::Newline
                && tok.kind != TokKind::Comment
                && (*at == from || !tok.glued)
        })
        .map(|(at, _)| at)
        .collect()
}

/// FUNCTION: The words after the event list, which is what the group
/// and the notation flag stand before.
///
/// Telling a group from an event is what the event table is for: the
/// word after the command is an event when the table holds it, and a
/// group when the word after it is one instead. A word the table does
/// not hold and that no event follows is read as the event anyway,
/// because a newer Vim adds events, and reading one as a group would
/// shift the pattern onto the command and drop a call the project
/// owns.
fn after_event<'a>(
    stmt: &'a [Tok],
    words: &'a [usize],
) -> Option<impl Iterator<Item = usize> + 'a> {
    let mut at = 1;

    // `:doautocmd <nomodeline> User X` states the flag before the rest.
    if words.get(at).is_some_and(|w| is_notation(stmt, *w)) {
        at += 1;
    }

    let here = *words.get(at)?;
    let next = words.get(at + 1).copied();

    if !is_event(stmt, here) && next.is_some_and(|w| is_event(stmt, w)) {
        at += 1;
    }

    // An event list that a space divides carries on: Vim writes
    // `WinEnter,WinLeave` without one, and the comma holds the list
    // together either way.
    while words
        .get(at)
        .is_some_and(|w| ends_in_comma(stmt, *w, words.get(at + 1).copied()))
    {
        at += 1;
    }

    at += 1;

    Some(words[at.min(words.len())..].iter().copied())
}

/// FUNCTION: Whether the word at `at` names an event, or stands for
/// every event in the forms that remove.
fn is_event(stmt: &[Tok], at: usize) -> bool {
    stmt[at].text == EVERY || events::has(&stmt[at].text)
}

fn is_flag(stmt: &[Tok], at: usize) -> bool {
    stmt[at].text == FLAG
}

fn is_notation(stmt: &[Tok], at: usize) -> bool {
    stmt[at].text == NOTATION
}

/// FUNCTION: Whether the word at `at` ends in a comma, so that the
/// word after it carries the same list on.
fn ends_in_comma(stmt: &[Tok], at: usize, next: Option<usize>) -> bool {
    let end = next.unwrap_or(stmt.len());

    stmt[at..end].last().is_some_and(|tok| tok.text == COMMA)
}

#[cfg(test)]
mod tests {
    use super::super::lex::tokens;
    use super::super::lex::Tok;
    use super::super::parse::statements;
    use super::body as body_at;
    use super::owned;

    /// FUNCTION: Whether the line's own syntax covers the token at `i`,
    /// for a statement whose command word opens it.
    fn owns(stmt: &[Tok], i: usize) -> bool {
        owned(stmt, 0).is_some_and(|own| own.contains(&i))
    }

    /// FUNCTION: Where the command an autocommand runs begins, for a
    /// statement whose command word opens it.
    fn body(stmt: &[Tok]) -> Option<usize> {
        body_at(stmt, 0)
    }

    /// FUNCTION: The one statement of a snippet, past the `vim9script`
    /// line every Vim9 file opens with.
    fn one(text: &str) -> Vec<Tok> {
        statements(&tokens(&format!("vim9script\n{text}\n")))
            .into_iter()
            .nth(1)
            .expect("the statement")
    }

    #[test]
    fn the_body_begins_after_the_pattern() {
        let stmt = one("autocmd BufRead *.fountain setfiletype fountain");

        assert_eq!(stmt[body(&stmt).expect("a body")].text, "setfiletype");
    }

    #[test]
    fn a_pattern_the_lexer_split_is_one_word() {
        let stmt = one("autocmd BufRead *.fountain setfiletype fountain");

        assert!(owns(&stmt, 3), "the dot of the glob");
        assert!(owns(&stmt, 4), "the fountain of the glob");
    }

    #[test]
    fn an_event_list_is_vims_from_end_to_end() {
        let stmt = one("autocmd WinEnter,WinLeave * Fn()");

        assert!(owns(&stmt, 1) && owns(&stmt, 3), "both event names");
    }

    #[test]
    fn a_group_stands_where_an_event_does_not() {
        let stmt = one("doautocmd Powerline ColorScheme");

        assert!(owns(&stmt, 1), "Powerline is a group, not an event");
        assert!(owns(&stmt, 2), "ColorScheme is an event");
        assert_eq!(body(&stmt), None);
    }

    #[test]
    fn a_user_events_name_is_the_plugins_own_word() {
        let stmt = one("autocmd User BartlebyTestAutoSave Fn()");

        assert!(owns(&stmt, 2), "the name of a user event");
        assert_eq!(stmt[body(&stmt).expect("a body")].text, "Fn");
    }

    #[test]
    fn a_flag_is_vims_and_the_body_follows_it() {
        let stmt = one("autocmd BufRead * ++once Fn()");

        assert_eq!(stmt[body(&stmt).expect("a body")].text, "Fn");
    }

    #[test]
    fn a_form_that_removes_rather_than_defines_has_no_body() {
        for text in ["autocmd!", "autocmd! *", "autocmd! * <buffer>"] {
            let stmt = one(text);
            assert_eq!(body(&stmt), None, "{text}");
        }
    }

    #[test]
    fn a_glob_that_ends_in_a_command_name_is_still_a_pattern() {
        let stmt = one("autocmd BufRead *.c Fn()");

        assert!(
            owns(&stmt, 4),
            "the c of *.c is the glob, not the c command"
        );
        assert_eq!(stmt[body(&stmt).expect("a body")].text, "Fn");
    }

    #[test]
    fn the_other_two_commands_take_the_same_parts() {
        let stmt = one("doautoall <nomodeline> User BartlebyReady");

        assert!(owns(&stmt, 1), "the nomodeline flag");
        assert!(owns(&stmt, 4), "the User event");
        assert!(owns(&stmt, 5), "the name of the user event");
        assert_eq!(body(&stmt), None);
    }

    #[test]
    fn a_statement_that_is_no_autocommand_is_not_ours() {
        let stmt = one("echo BufEnter");

        assert!(!owns(&stmt, 1));
        assert_eq!(body(&stmt), None);
    }
}
