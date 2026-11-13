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

// What opens the part of a name that only a run of the program can
// give, in an interpolated string and in a legacy curly-brace name.
const GAP: char = '{';

// What closes it.
const GAP_END: char = '}';

// What declares a constant.
const CONST: &str = "const";

// What gives a declaration its value.
const ASSIGN: &str = "=";

// What joins two strings, in Vim9 and in legacy script. A name that
// ends its string before one goes on in what follows.
const JOINS: &[&str] = &["..", "."];

// The key notation of a bar, which ends a command in a mapping as the
// bar itself does elsewhere.
const BAR_KEY: [&str; 3] = ["<", "bar", ">"];

// What opens a function body, and what closes one. A constant inside
// a body is a local of it.
const BODY: &[&str] = &["def", "function"];
const BODY_END: &[&str] = &["enddef", "endfunction"];

// The key under which `getbufinfo()`, `getwininfo()` and
// `gettabinfo()` give every variable of a buffer, a window or a tab,
// and each scope it can therefore hold, with the function that gives
// it. The key does not say which function it came from, and the
// functions are called far more often for something else, so the key
// is what credits. It credits a scope only in a project that calls
// the function of that scope, because without the call the key is one
// of a dictionary of the project.
// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/61
const VARIABLES: &str = "variables";
const HELD: &[(char, &str)] = &[
    ('b', "getbufinfo"),
    ('w', "getwininfo"),
    ('t', "gettabinfo"),
];

// What stands before a key: the dot of a member and the bracket of an
// index.
const DOT: &str = ".";
const INDEX: &str = "[";

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
    /// A name with a gap. `whole` is set where no part of the name
    /// is fixed, and `head` is then the scope alone, as `g:`.
    Fit {
        head: String,
        tail: String,
        whole: bool,
        /// The function the project must call for the read to hold.
        needs: Option<&'static str>,
    },
}

impl Spelling {
    /// METHOD: The full spelling, where the name has no gap.
    fn exact(&self) -> Option<&str> {
        match self {
            Self::Exact(name) => Some(name),
            Self::Fit { .. } => None,
        }
    }

    /// METHOD: Every variable of one scope.
    fn whole(scope: char) -> Self {
        Self::Fit {
            head: format!("{scope}{COLON}"),
            tail: String::new(),
            whole: true,
            needs: None,
        }
    }

    /// METHOD: Every variable of one scope, read from what a function
    /// gives, so only where the project calls that function.
    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/61
    fn held(scope: char, by: &'static str) -> Self {
        Self::Fit {
            head: format!("{scope}{COLON}"),
            tail: String::new(),
            whole: true,
            needs: Some(by),
        }
    }
}

/// FUNCTION: Whether a function gives every variable of a scope under
/// the key `variables`.
pub(super) fn gives_scope(name: &str) -> bool {
    HELD.iter().any(|(_, by)| *by == name)
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
pub(super) fn uses(stmt: &[Tok], consts: &Consts) -> Uses {
    let mut out = Uses::default();

    for run in runs(stmt) {
        let mut found = named(stmt, run.clone(), &mut out.taken);
        let keyed = called(stmt, run.clone(), consts, &mut found);
        quoted(stmt, run, &mut found);

        let written: Vec<String> = found
            .iter()
            .filter(|u| u.write)
            .filter_map(|u| u.spelling.exact().map(str::to_string))
            .collect();

        for u in found.iter_mut().filter(|u| u.write) {
            u.lead = u
                .spelling
                .exact()
                .is_some_and(|name| keyed.iter().any(|k| k == name));
        }

        found.retain(|u| {
            u.write
                || !u
                    .spelling
                    .exact()
                    .is_some_and(|name| written.iter().any(|w| w == name))
        });

        out.found.extend(found);
    }

    out
}

/// FUNCTION: The string constants of one file: each `const` at the
/// level of the script whose value is one plain string.
///
/// A project names a buffer variable once, as
/// `const PENDING = 'plugin_pending'`, and passes the constant where
/// Vim takes the name. A name two statements give two values is left
/// out, because the scan cannot tell which one a use means. A constant
/// of a function body is left out too: it is a local of that body, and
/// a parameter of another function may carry its name.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/55
pub(super) fn consts(stmts: &[Vec<Tok>]) -> Consts {
    let mut out = Consts::new();
    let mut twice: Vec<String> = Vec::new();

    let mut depth = 0usize;

    for stmt in stmts {
        let code: Vec<&Tok> = stmt
            .iter()
            .filter(|t| !matches!(t.kind, TokKind::Comment | TokKind::Newline))
            .collect();

        // The word that opens a body may stand behind `export` or
        // `static`, and a legacy one may be abbreviated.
        let opens = code.iter().take(2).any(|t| {
            t.kind == TokKind::Ident
                && (BODY.contains(&t.text.as_str())
                    || excmds::canonical(&t.text).is_some_and(|c| BODY.contains(&c)))
        });
        let closes = code.first().is_some_and(|t| {
            BODY_END.contains(&t.text.as_str())
                || excmds::canonical(&t.text).is_some_and(|c| BODY_END.contains(&c))
        });

        if closes {
            depth = depth.saturating_sub(1);
            continue;
        }

        if opens {
            depth += 1;
            continue;
        }

        if depth > 0 {
            continue;
        }

        let Some(at) = code.iter().take(2).position(|t| t.text == CONST) else {
            continue;
        };

        let (Some(name), Some(value)) = (code.get(at + 1), code.last()) else {
            continue;
        };

        let assigned = code.len() >= 2 && code[code.len() - 2].text == ASSIGN;

        if !assigned || name.kind != TokKind::Ident || value.kind != TokKind::Str {
            continue;
        }

        let text = unquote(&value.text);

        match out.get(&name.text) {
            Some(held) if *held != text => twice.push(name.text.clone()),
            _ => {
                out.insert(name.text.clone(), text);
            }
        }
    }

    for name in twice {
        out.remove(&name);
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
        let full = format!("{}{COLON}{name}", chars[i]);
        let rest = &chars[i + 2 + name.chars().count()..];

        if rest.first() != Some(&GAP) {
            out.push(Spelling::Exact(full));
            continue;
        }

        // The name runs into a gap, and what stands against the end
        // of the gap is the end of the name, where no second gap
        // follows it.
        let after: Vec<char> = rest
            .iter()
            .skip_while(|c| **c != GAP_END)
            .skip(1)
            .copied()
            .collect();
        let tail: String = after.iter().take_while(|c| word(**c)).collect();
        let again = after.get(tail.chars().count()) == Some(&GAP);

        out.push(Spelling::Fit {
            head: full,
            tail: if again { String::new() } else { tail },
            whole: false,
            needs: None,
        });
    }

    out
}

/// FUNCTION: The variables one command names through a function that
/// takes the name as a string. It answers the names a `get()` on a
/// scope read, which is what marks a write beside one as the lead.
fn called(stmt: &[Tok], run: Range<usize>, consts: &Consts, found: &mut Vec<Use>) -> Vec<String> {
    let mut keyed = Vec::new();

    // Where the scope of a `get()` stands, once its key was read.
    let mut answered: Vec<usize> = Vec::new();

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
            let dict = if piped {
                (i >= run.start + 3).then(|| i - 3..i - 1)
            } else {
                args.first().cloned()
            };

            let scope = dict.clone().and_then(|d| bare_scope(stmt, d));
            let key = args.get(usize::from(!piped));

            if let (Some(scope), Some(dict), Some(key)) = (scope, dict, key) {
                if let Some(spelling) = name_of(stmt, key.clone(), scope, consts) {
                    answered.push(dict.start);
                    keyed.extend(spelling.exact().map(str::to_string));
                    found.push(Use {
                        spelling,
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

        let Some(spelling) = name_of(stmt, arg.clone(), *scope, consts) else {
            continue;
        };

        let write = setter.is_some();

        // A variable the help documents is written for Vim to read,
        // and a write whose name has a gap declares nothing the scan
        // can name.
        if write && !spelling.exact().is_some_and(|name| !scopevars::has(name)) {
            continue;
        }

        found.push(Use {
            spelling,
            at: arg.start,
            write,
            lead: false,
        });
    }

    // The key `variables` of what an info function returns holds a
    // whole scope, as a member or as an index.
    for i in run.clone().skip(1) {
        let tok = &stmt[i];
        let before = stmt[i - 1].text.as_str();

        let key = match tok.kind {
            TokKind::Ident => tok.text == VARIABLES && before == DOT,
            TokKind::Str => unquote(&tok.text) == VARIABLES && before == INDEX,
            _ => false,
        };

        if key {
            found.extend(HELD.iter().map(|(scope, by)| Use {
                spelling: Spelling::held(*scope, by),
                at: i,
                write: false,
                lead: false,
            }));
        }
    }

    // A scope with no name behind it stands for every variable it
    // holds: `keys(g:)`, `g:[name]`, `var all = g:`, and the legacy
    // `g:{name}`. Either the command ends at the colon or something
    // that is no name stands against it. The scope of a `get()` whose
    // key was read above is the one exception.
    for i in run.clone() {
        let Some(scope) = (i + 1 < run.end)
            .then(|| bare_scope(stmt, i..i + 2))
            .flatten()
        else {
            continue;
        };

        let next = stmt.get(i + 2).filter(|_| i + 2 < run.end);
        let alone = next.is_none_or(|t| t.glued && t.kind != TokKind::Ident);
        let option = i > 0 && stmt[i - 1].text == OPTION && stmt[i].glued;

        if alone && !option && !answered.contains(&i) {
            found.push(Use {
                spelling: Spelling::whole(scope),
                at: i,
                write: false,
                lead: false,
            });
        }
    }

    keyed
}

/// FUNCTION: The variables one command names by their full spelling
/// inside a string, which is how a test hands a setting to another
/// Vim and how `exists()` asks for one.
fn quoted(stmt: &[Tok], run: Range<usize>, found: &mut Vec<Use>) {
    for i in run.clone() {
        if stmt[i].kind != TokKind::Str {
            continue;
        }

        let text = unquote(&stmt[i].text);

        let mut held = spellings(&text);

        // A name that ends its string before a join goes on in what
        // is joined to it: `'g:plugin_' .. kind`. Its end is not
        // known, and a scope alone there names any variable.
        let joined = stmt
            .get(i + 1)
            .filter(|_| i + 1 < run.end)
            .is_some_and(|t| JOINS.contains(&t.text.as_str()));

        if joined {
            if let Some(scope) = ends_in_scope(&text) {
                held.push(Spelling::whole(scope));
            } else if let Some(Spelling::Exact(name)) = held.last() {
                if text.ends_with(name.as_str()) {
                    let head = name.clone();
                    held.pop();
                    held.push(Spelling::Fit {
                        head,
                        tail: String::new(),
                        whole: false,
                        needs: None,
                    });
                }
            }
        }

        for spelling in held {
            found.push(Use {
                spelling,
                at: i,
                write: false,
                lead: false,
            });
        }
    }
}

/// FUNCTION: The scope a piece of text ends in, where no name stands
/// behind it, as the `g:` of `'let v = g:'`.
fn ends_in_scope(text: &str) -> Option<char> {
    let mut back = text.chars().rev();

    if back.next() != Some(':') {
        return None;
    }

    let scope = back.next().filter(|c| SCOPES.contains(c))?;
    let before = back.next();

    (!before.is_some_and(|c| c.is_ascii_alphanumeric() || ['_', ':', '&', '#', '.'].contains(&c)))
        .then_some(scope)
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

/// FUNCTION: How an argument spells the variable it names in a
/// scope, or none where it names an option.
///
/// One plain string is the name. A constant of the file that holds
/// one is the same. A string with a gap fixes the parts around the
/// gap. Anything else is a name only a run of the program gives, and
/// stands for every variable of the scope.
fn name_of(stmt: &[Tok], arg: Range<usize>, scope: char, consts: &Consts) -> Option<Spelling> {
    let first = &stmt[arg.start];

    let text = match first.kind {
        TokKind::Str => unquote(&first.text),
        TokKind::Ident if arg.len() == 1 => match consts.get(&first.text) {
            Some(held) => held.clone(),
            None => return Some(Spelling::whole(scope)),
        },
        _ => return Some(Spelling::whole(scope)),
    };

    if text.starts_with(OPTION_NAME) {
        return None;
    }

    let word = |s: &str| s.chars().all(|c| c.is_ascii_alphanumeric() || c == '_');

    if let Some((head, rest)) = text.split_once(GAP) {
        // What stands behind the last gap ends the name, unless more
        // is joined to the string.
        let joined = stmt[arg.start + 1..arg.end]
            .iter()
            .any(|t| JOINS.contains(&t.text.as_str()));
        let tail = match rest.rsplit_once(GAP_END) {
            Some((_, tail)) if !joined => tail,
            _ => "",
        };

        if !word(head) || !word(tail) {
            return Some(Spelling::whole(scope));
        }

        return Some(Spelling::Fit {
            head: format!("{scope}{COLON}{head}"),
            tail: tail.to_string(),
            whole: head.is_empty() && tail.is_empty(),
            needs: None,
        });
    }

    // A string followed by more is an expression, as `'p_' .. kind`.
    if arg.len() != 1 || text.is_empty() || !word(&text) {
        return Some(Spelling::whole(scope));
    }

    Some(Spelling::Exact(format!("{scope}{COLON}{text}")))
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

        let key = stmt.get(i..i + BAR_KEY.len()).is_some_and(|toks| {
            toks.iter()
                .zip(BAR_KEY)
                .all(|(t, want)| t.text.eq_ignore_ascii_case(want))
        });

        if key {
            out.push(from..i);
            from = i + BAR_KEY.len();
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

        // A legacy name may go on in braces, as `g:plugin_{kind}`,
        // and what the braces give is known only to a run.
        if next.is_some_and(|t| t.glued && t.text.starts_with(GAP)) {
            out.push(Use {
                spelling: Spelling::Fit {
                    head: name,
                    tail: String::new(),
                    whole: false,
                    needs: None,
                },
                at,
                write: false,
                lead: false,
            });

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
