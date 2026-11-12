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
    /// Set on the write that states what the variable is. Nothing sets
    /// it yet.
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
/// again, and a variable used for nothing else is unread. A command
/// ends at a bar, so the guard of `if !exists('g:x') | g:x = 1` is a
/// read of its own.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/55
pub(super) fn uses(stmt: &[Tok], _consts: &Consts) -> Uses {
    let mut out = Uses::default();

    for run in runs(stmt) {
        let mut found = named(stmt, run, &mut out.taken);

        let written: Vec<String> = found
            .iter()
            .filter(|u| u.write)
            .map(|u| match &u.spelling {
                Spelling::Exact(name) => name.clone(),
            })
            .collect();

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
