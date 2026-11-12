//! Scoped variables: which variables of `g:`, `b:`, `w:` and `t:` a
//! statement writes, and which it reads.
//!
//! License: GNU GPL 3.0

use std::collections::HashMap;
use std::ops::Range;

use super::excmds;
use super::lex::Tok;
use super::lex::TokKind;
use super::scopevars;

/// The scopes whose variables outlive a script and are shared by every
/// file that names them: global, buffer, window and tab.
pub(super) const SCOPES: &[char] = &['g', 'b', 'w', 't'];

// What stands between a scope letter and the name behind it.
const COLON: &str = ":";

// What Vim writes between two commands on one line.
const BAR: &str = "|";

// What opens an option, whose scope letter names no variable:
// `&g:textwidth` is the global value of `textwidth`.
const OPTION: &str = "&";

// What opens the arguments of a call.
const CALL: &str = "(";

// The command that removes a variable, which neither reads it nor
// declares it.
const UNLET: &str = "unlet";

// Every assignment, plain and compound. A compound one reads the
// variable before it writes it, and that read is one the statement
// makes of its own write, which credits nothing.
const ASSIGNS: &[&str] = &["=", "=<<", "+=", "-=", "*=", "/=", "%=", "..=", ".="];

// What passes the value before it to a call as its first argument.
const ARROW: &str = "->";

// What divides the arguments of a call.
const COMMA: &str = ",";

// What opens an option name where a function takes one in place of a
// variable name: `getbufvar(nr, '&modified')`.
const OPTION_NAME: char = '&';

// The functions that take a dictionary and a key. A scope is a
// dictionary, so `get(g:, 'x')` reads `g:x`.
const KEYED: &[&str] = &["get", "has_key"];

// The functions that read a variable of another buffer, window or tab
// by its name, each with the scope it reads and the place of the name
// among its arguments.
const GETTERS: &[(&str, char, usize)] = &[
    ("getbufvar", 'b', 1),
    ("getwinvar", 'w', 1),
    ("gettabvar", 't', 1),
    ("gettabwinvar", 'w', 2),
];

// The functions that write one, on the same terms.
const SETTERS: &[(&str, char, usize)] = &[
    ("setbufvar", 'b', 1),
    ("setwinvar", 'w', 1),
    ("settabvar", 't', 1),
    ("settabwinvar", 'w', 2),
];

/// The string constants of one file, by name.
pub(super) type Consts = HashMap<String, String>;

/// How a statement spells the variable it uses.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) enum Spelling {
    /// The full spelling, as `g:x`.
    Exact(String),
}

/// One use of a scoped variable.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct Use {
    pub spelling: Spelling,
    /// The token that carries the line of the use.
    pub at: usize,
    pub write: bool,
    /// Set on the write that states what the variable is: the one
    /// that takes the value the user gave it, as
    /// `g:x = get(g:, 'x', default)`.
    pub lead: bool,
}

/// Every use of a scoped variable in one statement.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub(super) struct Uses {
    pub found: Vec<Use>,
    /// The name tokens behind a scope, which are no bare names of the
    /// project and must not be emitted as such.
    pub taken: Vec<usize>,
}

/// FUNCTION: The scoped variables one statement writes and reads.
///
/// A read of a name is dropped where the same command writes that
/// name: `g:x = !g:x` and `g:x += 1` use the variable only to set it
/// again, and a variable used for nothing else is unread. The `get()`
/// of `g:x = get(g:, 'x', default)` is such a read, and it marks the
/// write as the one that states what the variable is. A command ends
/// at a bar, so the guard of `if !exists('g:x') | g:x = 1` is a read
/// of its own.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/55
pub(super) fn uses(stmt: &[Tok], _consts: &Consts) -> Uses {
    let mut out = Uses::default();

    for run in runs(stmt) {
        let mut found = named(stmt, run.clone(), &mut out.taken);
        let keyed = called(stmt, run.clone(), &mut found);
        quoted(stmt, run, &mut found);

        let written: Vec<String> = found
            .iter()
            .filter(|u| u.write)
            .map(|u| match &u.spelling {
                Spelling::Exact(name) => name.clone(),
            })
            .collect();

        for u in found.iter_mut().filter(|u| u.write) {
            let Spelling::Exact(name) = &u.spelling;
            u.lead = keyed.contains(name);
        }

        found.retain(|u| {
            u.write
                || match &u.spelling {
                    Spelling::Exact(name) => !written.contains(name),
                }
        });

        out.found.extend(found);
    }

    out
}

/// FUNCTION: Every full spelling a piece of text holds, as the `g:x`
/// of `'g:x = true'`.
///
/// A spelling starts where a word starts. `config:value` holds a `g`
/// against a colon and names no variable.
pub(super) fn spellings(text: &str) -> Vec<Spelling> {
    let chars: Vec<char> = text.chars().collect();
    let word = |c: char| c.is_ascii_alphanumeric() || c == '_';
    let mut out = Vec::new();

    for i in 0..chars.len() {
        let opens = SCOPES.contains(&chars[i])
            && chars.get(i + 1) == Some(&':')
            && chars
                .get(i + 2)
                .is_some_and(|c| c.is_ascii_alphabetic() || *c == '_')
            && (i == 0 || !(word(chars[i - 1]) || [':', '&', '#', '.'].contains(&chars[i - 1])));

        if !opens {
            continue;
        }

        let name: String = chars[i + 2..].iter().take_while(|c| word(**c)).collect();
        out.push(Spelling::Exact(format!("{}{COLON}{name}", chars[i])));
    }

    out
}

/// FUNCTION: The variables one command names through a function that
/// takes the name as a string. It answers the names a `get()` on a
/// scope read, which is what marks a write beside one as the lead.
fn called(stmt: &[Tok], run: Range<usize>, found: &mut Vec<Use>) -> Vec<String> {
    let mut keyed = Vec::new();

    for i in run.clone() {
        let opens = stmt[i].kind == TokKind::Ident
            && stmt
                .get(i + 1)
                .is_some_and(|t| t.text == CALL && t.glued && i + 1 < run.end);

        if !opens {
            continue;
        }

        let word = stmt[i].text.as_str();
        let args = args(stmt, i + 1, run.end);

        // A value before an arrow is the first argument, so every
        // argument in the brackets stands one place earlier.
        let piped = i > run.start && stmt[i - 1].text == ARROW;

        if KEYED.contains(&word) {
            let scope = if piped {
                (i >= run.start + 3)
                    .then(|| bare_scope(stmt, i - 3..i - 1))
                    .flatten()
            } else {
                args.first().and_then(|a| bare_scope(stmt, a.clone()))
            };

            let key = args.get(usize::from(!piped));

            if let (Some(scope), Some(key)) = (scope, key) {
                if let Some(name) = name_of(stmt, key.clone(), scope) {
                    keyed.push(name.clone());
                    found.push(Use {
                        spelling: Spelling::Exact(name),
                        at: key.start,
                        write: false,
                        lead: false,
                    });
                }
            }

            continue;
        }

        let getter = GETTERS.iter().find(|(name, _, _)| *name == word);
        let setter = SETTERS.iter().find(|(name, _, _)| *name == word);

        let Some((_, scope, place)) = getter.or(setter) else {
            continue;
        };

        let Some(arg) = place
            .checked_sub(usize::from(piped))
            .and_then(|n| args.get(n))
        else {
            continue;
        };

        let Some(name) = name_of(stmt, arg.clone(), *scope) else {
            continue;
        };

        let write = setter.is_some();

        if write && scopevars::has(&name) {
            continue;
        }

        found.push(Use {
            spelling: Spelling::Exact(name),
            at: arg.start,
            write,
            lead: false,
        });
    }

    keyed
}

/// FUNCTION: The variables one command names by their full spelling
/// inside a string, which is how a test hands a setting to another
/// Vim and how `exists()` asks for one.
fn quoted(stmt: &[Tok], run: Range<usize>, found: &mut Vec<Use>) {
    for i in run {
        if stmt[i].kind != TokKind::Str {
            continue;
        }

        for spelling in spellings(&unquote(&stmt[i].text)) {
            found.push(Use {
                spelling,
                at: i,
                write: false,
                lead: false,
            });
        }
    }
}

/// FUNCTION: The arguments of a call, each as the range of its tokens,
/// from the bracket that opens them.
fn args(stmt: &[Tok], open: usize, end: usize) -> Vec<Range<usize>> {
    let mut out = Vec::new();
    let mut depth = 0usize;
    let mut from = open + 1;

    for (i, tok) in stmt.iter().enumerate().take(end).skip(open) {
        // A string may hold a bracket, and it is text there.
        if tok.kind == TokKind::Str {
            continue;
        }

        match tok.text.as_str() {
            "(" | "[" | "{" => depth += 1,
            ")" | "]" | "}" => {
                depth = depth.saturating_sub(1);

                if depth == 0 {
                    if from < i {
                        out.push(from..i);
                    }

                    return out;
                }
            }
            COMMA if depth == 1 => {
                out.push(from..i);
                from = i + 1;
            }
            _ => {}
        }
    }

    out
}

/// FUNCTION: The scope an argument names where it is a scope and
/// nothing more, as the `g:` of `get(g:, 'x')`.
fn bare_scope(stmt: &[Tok], arg: Range<usize>) -> Option<char> {
    if arg.len() != 2 {
        return None;
    }

    let mut letters = stmt[arg.start].text.chars();
    let letter = letters.next().filter(|c| SCOPES.contains(c))?;
    let colon = &stmt[arg.start + 1];

    (letters.next().is_none() && colon.text == COLON && colon.glued).then_some(letter)
}

/// FUNCTION: The full spelling an argument names in a scope, where the
/// argument is one plain string. An option name is no variable.
fn name_of(stmt: &[Tok], arg: Range<usize>, scope: char) -> Option<String> {
    if arg.len() != 1 || stmt[arg.start].kind != TokKind::Str {
        return None;
    }

    let name = unquote(&stmt[arg.start].text);
    let plain = !name.is_empty() && name.chars().all(|c| c.is_ascii_alphanumeric() || c == '_');

    (plain && !name.starts_with(OPTION_NAME)).then(|| format!("{scope}{COLON}{name}"))
}

/// FUNCTION: A string token without its quotes.
fn unquote(text: &str) -> String {
    let mut chars = text.chars();
    chars.next();
    chars.next_back();
    chars.collect()
}

/// FUNCTION: The commands of one statement, each as the range of its
/// tokens.
fn runs(stmt: &[Tok]) -> Vec<Range<usize>> {
    let mut out = Vec::new();
    let mut from = 0;

    for (i, tok) in stmt.iter().enumerate() {
        if tok.text == BAR {
            out.push(from..i);
            from = i + 1;
        }
    }

    out.push(from..stmt.len());
    out
}

/// FUNCTION: The variables one command names by scope and name, as
/// `g:x`.
fn named(stmt: &[Tok], run: Range<usize>, taken: &mut Vec<usize>) -> Vec<Use> {
    let removes = stmt[run.clone()]
        .first()
        .is_some_and(|t| excmds::canonical(&t.text) == Some(UNLET));

    let mut out = Vec::new();

    for i in run.clone() {
        let Some(scope) = scope_at(stmt, i, run.end) else {
            continue;
        };

        let at = i + 2;
        let name = format!("{scope}{COLON}{}", stmt[at].text);
        let next = stmt.get(at + 1).filter(|_| at + 1 < run.end);

        // A call through a scope may be a legacy function declared as
        // `g:Name`, which its bare name still has to credit.
        if !next.is_some_and(|t| t.text == CALL && t.glued) {
            taken.push(at);
        }

        if removes {
            continue;
        }

        let write = next.is_some_and(|t| ASSIGNS.contains(&t.text.as_str()));

        // A variable the help documents is written for Vim, or for a
        // plugin Vim ships, to read.
        if write && scopevars::has(&name) {
            continue;
        }

        out.push(Use {
            spelling: Spelling::Exact(name),
            at,
            write,
            lead: false,
        });
    }

    out
}

/// FUNCTION: The scope letter at a position, where a name stands
/// against it: three tokens with no space between them.
///
/// The space is what tells a scope from the other colons Vim9 writes.
/// `{g: 1}`, `(b: number) => b` and `ok ? g : b` all hold a letter and
/// a colon, and none of them a name against the colon.
fn scope_at(stmt: &[Tok], i: usize, end: usize) -> Option<char> {
    if i + 2 >= end {
        return None;
    }

    let mut letters = stmt[i].text.chars();
    let letter = letters.next().filter(|c| SCOPES.contains(c))?;

    if letters.next().is_some() || stmt[i].kind != TokKind::Ident {
        return None;
    }

    if i > 0 && stmt[i - 1].text == OPTION && stmt[i].glued {
        return None;
    }

    let colon = &stmt[i + 1];
    let name = &stmt[i + 2];

    (colon.text == COLON && colon.glued && name.kind == TokKind::Ident && name.glued)
        .then_some(letter)
}
