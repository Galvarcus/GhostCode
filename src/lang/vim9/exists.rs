//! The argument of `exists()`, read part by part: which name it holds
//! and whether that name is Vim's own word.
//!
//! License: GNU GPL 3.0

use super::parse::identifiers;
use super::shared::SCOPES as SHARED;

/// What opens an option name, as `exists('&relativenumber')`.
const OPTION: char = '&';

/// What opens a compile-time feature, as `exists('+shellslash')`.
const FEATURE: char = '+';

/// What opens an environment variable, as `exists('$HOME')`.
const ENV: char = '$';

/// What opens a function name, as `exists('*Open')`.
const FUNCTION: char = '*';

/// What opens a command name, as `exists(':Recover')`.
const COMMAND: char = ':';

/// What opens an autocommand group or event, as `exists('#User#')`.
const AUTOCMD: char = '#';

/// The scopes Vim writes before a colon. Only `s:` can carry a symbol
/// the project declares, because a script-local variable is one and a
/// global, buffer, window, tab, Vim, argument or legacy-local variable
/// is not.
const SCOPES: &[char] = &['s', 'g', 'b', 'w', 't', 'v', 'a', 'l'];

/// The one scope whose name may be a symbol of the project's.
const SCRIPT: char = 's';

/// FUNCTION: The names the argument of `exists()` holds, each with
/// whether it is Vim's own word rather than one the project could
/// declare.
///
/// A name flagged as Vim's is marked by the caller, so it stops being
/// counted as unplaced while a project symbol of that spelling still
/// takes the credit. A scope prefix, a sigil and an autocommand group
/// are Vim's syntax rather than names, and do not come back at all.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
pub fn names(arg: &str) -> Vec<(String, bool)> {
    let arg = arg.trim();
    let Some(first) = arg.chars().next() else {
        return Vec::new();
    };

    let rest = &arg[first.len_utf8()..];

    match first {
        AUTOCMD => Vec::new(),
        OPTION => vims(past_scope(rest)),
        FEATURE | ENV => vims(rest),
        FUNCTION if builtin(rest) => vims(rest),
        FUNCTION | COMMAND => theirs(rest),
        _ => match scope(arg) {
            Some((SCRIPT, name)) => theirs(name),
            // A variable every file shares is read by its full
            // spelling, which the scan of the statement finds in the
            // string. The name behind the scope is no bare name.
            // REFERENCE: https://github.com/Galvarcus/GhostCode/issues/55
            Some((letter, _)) if SHARED.contains(&letter) => Vec::new(),
            Some((_, name)) => vims(name),
            None => theirs(arg),
        },
    }
}

/// FUNCTION: The scope a name stands behind, and the name itself.
fn scope(arg: &str) -> Option<(char, &str)> {
    let mut chars = arg.chars();
    let letter = chars.next()?;

    if chars.next() != Some(COMMAND) || !SCOPES.contains(&letter) {
        return None;
    }

    Some((letter, &arg[letter.len_utf8() + COMMAND.len_utf8()..]))
}

/// FUNCTION: An option may carry a scope of its own, as `&l:textwidth`
/// does, and the option's name stands behind it.
fn past_scope(rest: &str) -> &str {
    scope(rest).map_or(rest, |(_, name)| name)
}

/// FUNCTION: Whether a function name is one only Vim can carry. Vim
/// refuses a function of a plugin whose name opens with a lowercase
/// letter, unless the name is an autoload one.
fn builtin(name: &str) -> bool {
    name.starts_with(|c: char| c.is_ascii_lowercase()) && !name.contains(AUTOCMD)
}

fn vims(text: &str) -> Vec<(String, bool)> {
    identifiers(text).into_iter().map(|n| (n, true)).collect()
}

fn theirs(text: &str) -> Vec<(String, bool)> {
    identifiers(text).into_iter().map(|n| (n, false)).collect()
}

#[cfg(test)]
mod tests {
    use super::names;

    #[test]
    fn a_scope_prefix_is_not_a_name() {
        assert_eq!(names("s:is_loaded"), vec![("is_loaded".to_string(), false)]);
    }

    #[test]
    fn a_global_guard_holds_no_bare_name() {
        assert!(names("g:loaded_x").is_empty());
    }

    #[test]
    fn an_option_and_a_feature_are_vims_own_words() {
        assert_eq!(
            names("&relativenumber"),
            vec![("relativenumber".to_string(), true)]
        );
        assert_eq!(names("+shellslash"), vec![("shellslash".to_string(), true)]);
    }

    #[test]
    fn an_option_behind_a_scope_of_its_own_is_still_one_name() {
        assert_eq!(names("&l:textwidth"), vec![("textwidth".to_string(), true)]);
    }

    #[test]
    fn a_function_or_a_command_may_be_the_projects() {
        assert_eq!(names("*Func"), vec![("Func".to_string(), false)]);
        assert_eq!(names(":Recover"), vec![("Recover".to_string(), false)]);
    }

    #[test]
    fn an_autoload_function_keeps_its_whole_name() {
        assert_eq!(
            names("*bartleby#Open"),
            vec![("bartleby#Open".to_string(), false)]
        );
    }

    #[test]
    fn an_autocommand_group_holds_no_name() {
        assert!(names("#User#").is_empty());
        assert!(names("#bartleby_follow#BufEnter").is_empty());
    }

    /// Vim refuses a function of the project whose name opens with a
    /// lowercase letter, unless the name is an autoload one.
    #[test]
    fn a_builtin_behind_the_function_sigil_is_vims() {
        assert_eq!(names("*strptime"), vec![("strptime".to_string(), true)]);
    }

    #[test]
    fn a_function_with_a_capital_behind_the_function_sigil_is_not_vims() {
        assert_eq!(names("*Open"), vec![("Open".to_string(), false)]);
    }
}
