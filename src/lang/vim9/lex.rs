//! The Vim9 lexer: source text to tokens, with physical line numbers.
//!
//! License: GNU GPL 3.0

use crate::lang::vim9::excmds;
use crate::lang::vim9::parse;

/// What a token is. There is no keyword kind: a word is a word, and the
/// parser decides whether its position makes it `def` the command or
/// `def` the name of something.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum TokKind {
    Ident,
    Str,
    Num,
    Op,
    Punct,
    Comment,
    /// The body of a heredoc, one token per physical line, so that its
    /// text is never read as code.
    Heredoc,
    /// The end of a statement, which is not the end of every physical
    /// line: a continued line carries on.
    Newline,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Tok {
    pub kind: TokKind,
    pub text: String,
    pub line: u32,
    /// Whether no space stood between this token and the one before
    /// it. A rule needs it to tell `*.fountain`, which is one word of
    /// a pattern, from `* Fn()`, where a space divides the pattern
    /// from the command after it. A column would not answer: the text
    /// of a string token is not the length of its source.
    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
    pub glued: bool,
}

// The command that makes the rest of a script Vim9. The lines before
// it are legacy script.
const VIM9: &str = "vim9script";

// The words that open and close a body. A `def` body is Vim9 and a
// `function` body is legacy script, whatever the script around it is.
// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/67
const DEF: &str = "def";
const ENDDEF: &str = "enddef";
const FUNCTION: &str = "function";
const ENDFUNCTION: &str = "endfunction";

// What can stand between `function` and the name it defines, and
// what opens the parameters behind the name.
const BANG: char = '!';
const PARAMS: char = '(';

// The marker of a comment in legacy script, and the marker of one
// that stands between the lines of a continued command.
const LEGACY_COMMENT: char = '"';
const LEGACY_CARRIED: &str = "\"\\ ";

// What stands against the name of a key in a dictionary.
// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/116
const KEY_COLON: char = ':';

// The words that open or close a block. A bracket left unclosed by a
// broken line must not swallow the file, so one of these at the start
// of a line ends the statement before it, whatever the bracket depth.
const RESYNC: &[&str] = &[
    VIM9,
    DEF,
    ENDDEF,
    "class",
    "endclass",
    "enum",
    "endenum",
    "interface",
    "endinterface",
    "export",
    "var",
    "const",
    "final",
    "if",
    "elseif",
    "else",
    "endif",
    "for",
    "endfor",
    "while",
    "endwhile",
    "try",
    "catch",
    "finally",
    "endtry",
    "return",
    FUNCTION,
    ENDFUNCTION,
    "import",
    "augroup",
    "command",
    "autocmd",
];

// What ends the keys of a mapping, and what stands before one that
// ends nothing.
// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/52
const BAR: char = '|';
const ESCAPE: char = '\\';

// The operators of more than one character, longest first, so that `..`
// never reads as two member dots and `==#` never as `==` and `#`.
const OPS: &[&str] = &[
    "=<<", "...", "->>", "==#", "==?", "!=#", "!=?", "=~#", "=~?", "!~#", "!~?", "<=#", ">=#",
    "..=", "<<=", ">>=", "->", "=>", "..", "==", "!=", "<=", ">=", "&&", "||", "+=", "-=", "*=",
    "/=", "%=", "=~", "!~", "<<", ">>", "??", "?.",
];

/// FUNCTION: Every token of one file, in order, each carrying the
/// physical line it sits on, because every line the analyzer reports
/// must match the line the old one reported.
pub fn tokens(text: &str) -> Vec<Tok> {
    let mut toks: Vec<Tok> = Vec::new();
    let mut depth: i32 = 0;
    let mut heredoc: Option<String> = None;
    // Whether the line before ended inside the keys of a mapping, which
    // a line that opens with a backslash carries on.
    let mut keys = false;
    // Whether no `vim9script` line stands above the line being read,
    // and the body the line stands in, where it stands in one.
    let mut script_legacy = true;
    let mut body: Option<Body> = None;

    for (i, raw) in text.lines().enumerate() {
        let line = i as u32 + 1;

        // A heredoc body belongs to its terminator, not to the grammar.
        if let Some(term) = &heredoc {
            if raw.trim() == term.as_str() {
                heredoc = None;
            } else {
                toks.push(Tok {
                    kind: TokKind::Heredoc,
                    text: raw.to_string(),
                    line,
                    glued: false,
                });
            }
            continue;
        }

        let mut rest = raw.trim_start();

        script_legacy = script_legacy && !opens_with(rest, VIM9);
        body = body_at(body, rest);

        let legacy = match body {
            Some(Body::Legacy) => true,
            Some(Body::Vim9) => false,
            None => script_legacy,
        };

        // A comment between the lines of a continued command leaves
        // nothing behind, so the line after it carries the command on
        // as if the comment were not there. The marker opens no string
        // a script would write, so it holds inside brackets as well.
        // REFERENCE: https://github.com/Galvarcus/GhostCode/issues/67
        if legacy && rest.starts_with(LEGACY_CARRIED) {
            continue;
        }

        // Legacy script marks a comment with a double quote, so a
        // line that opens with one is no string, and a name in it is
        // no use of the name. Inside brackets the line is read as
        // before, because a bracket left open by a broken line must
        // not turn a string into a comment.
        // REFERENCE: https://github.com/Galvarcus/GhostCode/issues/60
        if legacy && depth == 0 && rest.starts_with(LEGACY_COMMENT) {
            toks.push(Tok {
                kind: TokKind::Comment,
                text: rest.to_string(),
                line,
                glued: false,
            });
            push_newline(&mut toks, line);
            continue;
        }

        let carried = keys && rest.starts_with('\\');

        // A line that opens with a backslash, or with an arrow, carries
        // the line before it on, so the statement did not end there.
        if rest.starts_with('\\') {
            rest = &rest[1..];
            pop_newline(&mut toks);
        } else if rest.starts_with("->") || rest.starts_with("|") {
            pop_newline(&mut toks);
        } else if depth > 0 && opens_block(rest) {
            depth = 0;
            push_newline(&mut toks, line.saturating_sub(1));
        }

        // Whether a line is a mapping is a question about its tokens,
        // so the line is read once as code to ask it. Nothing before
        // the command differs between the two readings, and what
        // stands behind it is read again as keys.
        // REFERENCE: https://github.com/Galvarcus/GhostCode/issues/52
        let from = toks.len();
        let was = (depth, heredoc.clone());
        let start = if carried {
            Some(0)
        } else {
            lex_line(rest, line, &mut toks, &mut depth, &mut heredoc, None);
            parse::map_at(&toks[from..]).map(|at| at + 1)
        };

        keys = false;

        if start.is_some() {
            toks.truncate(from);
            (depth, heredoc) = was;
            keys = lex_line(rest, line, &mut toks, &mut depth, &mut heredoc, start);
        }

        // Inside brackets the statement continues on the next line.
        if depth <= 0 {
            depth = 0;
            push_newline(&mut toks, line);
        }
    }

    push_newline(&mut toks, text.lines().count() as u32);
    toks
}

/// FUNCTION: True when a line opens or closes a block, which ends any
/// statement a broken line left open. A word with a colon against it
/// is the key of a dictionary, as `command: 'x',` is, and opens
/// nothing.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/116
fn opens_block(line: &str) -> bool {
    RESYNC.iter().any(|word| {
        opens_with(line, word) && !line.trim_start()[word.len()..].starts_with(KEY_COLON)
    })
}

/// The kind of body a line stands in.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Body {
    Vim9,
    Legacy,
}

/// FUNCTION: The body a line stands in, from the body of the line
/// before it.
///
/// A body is closed only by the word that closes its own kind, so a
/// word of the other kind inside it changes nothing. `function` is
/// read with its abbreviations, and only where a name and its
/// parameters follow, because `fu` is a name a script can give a
/// variable.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/67
fn body_at(body: Option<Body>, line: &str) -> Option<Body> {
    let word = first_word(line);
    let command = excmds::canonical(word);

    match body {
        None if word == DEF => Some(Body::Vim9),
        None if command == Some(FUNCTION) && defines(&line[word.len()..]) => Some(Body::Legacy),
        Some(Body::Vim9) if word == ENDDEF => None,
        Some(Body::Legacy) if command == Some(ENDFUNCTION) => None,
        _ => body,
    }
}

/// FUNCTION: Whether what stands behind `function` defines one: a
/// name, with or without a bang before it, and its parameters.
fn defines(rest: &str) -> bool {
    let rest = rest.strip_prefix(BANG).unwrap_or(rest);
    let name = rest.trim_start();

    name.len() < rest.len()
        && name.starts_with(|c: char| c.is_ascii_alphabetic() || c == '_' || c == '<')
        && name.contains(PARAMS)
}

/// FUNCTION: The first word of a line.
fn first_word(line: &str) -> &str {
    let len = line
        .chars()
        .take_while(|c| c.is_ascii_alphanumeric() || *c == '_')
        .count();

    &line[..len]
}

/// FUNCTION: Whether the first word of a line is this one.
fn opens_with(line: &str, word: &str) -> bool {
    first_word(line) == word
}

/// FUNCTION: Add one token of the line, recording whether a space
/// stood before it, and open a fresh gap for the next one.
fn push_tok(toks: &mut Vec<Tok>, kind: TokKind, text: String, line: u32, gap: &mut bool) {
    toks.push(Tok {
        kind,
        text,
        line,
        glued: !std::mem::replace(gap, false),
    });
}

/// FUNCTION: Tokenise one logical line's worth of text, and answer
/// whether it ended inside the keys of a mapping.
///
/// `keys_from` is the number of tokens of the line behind which the
/// keys of a mapping command begin, or none where the line holds no
/// such command. Keys run to a bar that no backslash escapes. Among
/// them a `#` opens no comment, a bracket opens nothing and `=<<`
/// opens no heredoc, because a mapping command takes its arguments as
/// they stand.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/52
fn lex_line(
    text: &str,
    line: u32,
    toks: &mut Vec<Tok>,
    depth: &mut i32,
    heredoc: &mut Option<String>,
    keys_from: Option<usize>,
) -> bool {
    let src: Vec<char> = text.chars().collect();
    let base = toks.len();
    let mut ended = false;
    let mut keys = false;
    let mut i = 0;
    let mut heredoc_here = false;
    // The line's first token stands behind the indent, so nothing is
    // glued to it.
    let mut gap = true;

    while i < src.len() {
        let c = src[i];

        if c.is_whitespace() {
            gap = true;
            i += 1;
            continue;
        }

        if keys && c == BAR && (i == 0 || src[i - 1] != ESCAPE) {
            ended = true;
        }

        keys = !ended && keys_from.is_some_and(|n| toks.len() - base >= n);

        // A comment runs to the end of the line. In Vim9 the marker is
        // `#`, and a double quote opens a string. A hash against a
        // name belongs to it: `bartleby#Open` is the classic autoload
        // calling convention, not a name and a comment.
        if c == '#' && !keys && (i == 0 || src[i - 1].is_whitespace()) {
            push_tok(
                toks,
                TokKind::Comment,
                src[i..].iter().collect(),
                line,
                &mut gap,
            );
            break;
        }

        // `$'a {expr} b'` is a string whose braces hold code. The
        // literal part is text, and what the braces hold is read as
        // code, because a name used only there is still used.
        if c == '$' && matches!(src.get(i + 1), Some('\'') | Some('"')) {
            let quote = src[i + 1];
            let (text, next) = lex_str(&src, i + 1, quote);
            lex_interpolated(&text, line, toks, depth, heredoc);
            i = next;
            continue;
        }

        if c == '\'' || c == '"' {
            let (text, next) = lex_str(&src, i, c);
            push_tok(toks, TokKind::Str, text, line, &mut gap);
            i = next;
            continue;
        }

        if c.is_ascii_digit() {
            let start = i;
            while i < src.len()
                && (src[i].is_ascii_alphanumeric() || (src[i] == '.' && is_num_dot(&src, i)))
            {
                i += 1;
            }
            push_tok(
                toks,
                TokKind::Num,
                src[start..i].iter().collect(),
                line,
                &mut gap,
            );
            continue;
        }

        if is_ident_start(c) && (!is_sigil(c) || src.get(i + 1).is_some_and(|n| is_ident(*n))) {
            let start = i;

            // The first character is skipped rather than tested,
            // because a sigil is not a name character and the loop
            // would consume nothing and never advance: `&cp`,
            // `$HOME`, `@a`.
            i += 1;
            while i < src.len() && is_ident(src[i]) {
                i += 1;
            }
            push_tok(
                toks,
                TokKind::Ident,
                src[start..i].iter().collect(),
                line,
                &mut gap,
            );
            continue;
        }

        if let Some(op) = op_at(&src, i) {
            if op == "=<<" && !keys {
                heredoc_here = true;
            }
            i += op.chars().count();
            push_tok(toks, TokKind::Op, op.to_string(), line, &mut gap);
            continue;
        }

        match c {
            '(' | '[' | '{' if !keys => *depth += 1,
            ')' | ']' | '}' if !keys => *depth -= 1,
            _ => {}
        }

        let kind = match c {
            '(' | ')' | '[' | ']' | '{' | '}' | ',' | ';' | ':' => TokKind::Punct,
            _ => TokKind::Op,
        };
        push_tok(toks, kind, c.to_string(), line, &mut gap);
        i += 1;
    }

    if heredoc_here {
        // The terminator is the last word of the line: `=<< trim END`
        // and `=<< END` both end at END.
        *heredoc = toks
            .iter()
            .rev()
            .find(|t| t.kind == TokKind::Ident && t.line == line)
            .map(|t| t.text.clone());
    }

    !ended && keys_from.is_some_and(|n| toks.len() - base >= n)
}

/// FUNCTION: Tokenise an interpolated string: its literal text as one
/// string token, and each braced part as the code it is.
///
/// A doubled brace escapes itself and holds no code, which is how Vim9
/// writes a literal brace.
fn lex_interpolated(
    text: &str,
    line: u32,
    toks: &mut Vec<Tok>,
    depth: &mut i32,
    heredoc: &mut Option<String>,
) {
    toks.push(Tok {
        kind: TokKind::Str,
        text: text.to_string(),
        line,
        glued: false,
    });

    let chars: Vec<char> = text.chars().collect();
    let mut i = 0;

    while i < chars.len() {
        if chars[i] != '{' {
            i += 1;
            continue;
        }

        if chars.get(i + 1) == Some(&'{') {
            i += 2;
            continue;
        }

        let start = i + 1;
        let mut end = start;
        while end < chars.len() && chars[end] != '}' {
            end += 1;
        }

        let code: String = chars[start..end].iter().collect();
        let mut inner = 0i32;
        lex_line(&code, line, toks, &mut inner, heredoc, None);

        i = end + 1;
    }

    let _ = depth;
}

/// FUNCTION: Read one string literal whole, so that nothing inside it
/// reaches the grammar. A single-quoted string takes no escape, and
/// doubles its quote to hold one; a double-quoted string escapes.
fn lex_str(src: &[char], start: usize, quote: char) -> (String, usize) {
    let mut i = start + 1;

    while i < src.len() {
        let c = src[i];

        if quote == '"' && c == '\\' {
            i += 2;
            continue;
        }

        if c == quote {
            if quote == '\'' && src.get(i + 1) == Some(&'\'') {
                i += 2;
                continue;
            }
            i += 1;
            return (src[start..i].iter().collect(), i);
        }

        i += 1;
    }

    // Unterminated: the line ends it, so that one bad line costs one
    // line rather than the rest of the file.
    (src[start..].iter().collect(), src.len())
}

/// FUNCTION: The operator at a position, longest first, or none.
fn op_at(src: &[char], i: usize) -> Option<&'static str> {
    let rest: String = src[i..].iter().take(3).collect();
    OPS.iter().copied().find(|op| rest.starts_with(op))
}

/// FUNCTION: True when a dot at a position is part of a number, as in
/// `1.5`, rather than a member access or a concatenation.
fn is_num_dot(src: &[char], i: usize) -> bool {
    src.get(i + 1).is_some_and(char::is_ascii_digit)
}

fn is_ident_start(c: char) -> bool {
    c.is_ascii_alphabetic() || c == '_' || is_sigil(c)
}

/// FUNCTION: True when a character opens a name of Vim's own, which
/// is a name it cannot appear inside.
///
/// A sigil with no name after it is punctuation, and reading it as a
/// name of one character costs the operator that starts with it:
/// `&&` lexed as two names before this rule, and every one of them
/// was counted as a reference that resolved to nothing.
fn is_sigil(c: char) -> bool {
    c == '&' || c == '$' || c == '@'
}

// A scope prefix such as `g:` is three tokens, not one, because Vim9
// writes a type annotation as `x: Foo` with the colon against the name,
// and an identifier that swallowed a colon would swallow that too.
fn is_ident(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '_' || c == '#'
}

/// FUNCTION: End the statement, unless it is already ended or nothing
/// has started it.
fn push_newline(toks: &mut Vec<Tok>, line: u32) {
    if toks.is_empty() || toks.last().is_some_and(|t| t.kind == TokKind::Newline) {
        return;
    }
    toks.push(Tok {
        kind: TokKind::Newline,
        text: String::new(),
        line,
        glued: false,
    });
}

/// FUNCTION: Undo the end of a statement, for a line that continues it.
fn pop_newline(toks: &mut Vec<Tok>) {
    if toks.last().is_some_and(|t| t.kind == TokKind::Newline) {
        toks.pop();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// FUNCTION: The text of every token of a kind, for an assertion
    /// that names what it expects rather than a token index.
    fn texts(toks: &[Tok], kind: TokKind) -> Vec<&str> {
        toks.iter()
            .filter(|t| t.kind == kind)
            .map(|t| t.text.as_str())
            .collect()
    }

    #[test]
    fn a_hash_comment_is_one_token() {
        let toks = tokens("var x = 1 # why it is one\n");

        assert_eq!(texts(&toks, TokKind::Comment), vec!["# why it is one"]);
    }

    #[test]
    fn a_logical_and_is_one_operator() {
        let toks = tokens("if a && b\n");

        assert_eq!(texts(&toks, TokKind::Ident), vec!["if", "a", "b"]);
        assert_eq!(texts(&toks, TokKind::Op), vec!["&&"]);
    }

    #[test]
    fn an_option_still_lexes_as_one_name() {
        let toks = tokens("if &cp && !&wrap\n");

        assert_eq!(texts(&toks, TokKind::Ident), vec!["if", "&cp", "&wrap"]);
    }

    #[test]
    fn a_hash_inside_a_string_is_not_a_comment() {
        let toks = tokens("var x = 'a # b'\n");

        assert!(texts(&toks, TokKind::Comment).is_empty());
        assert_eq!(texts(&toks, TokKind::Str), vec!["'a # b'"]);
    }

    #[test]
    fn a_single_quoted_string_keeps_its_backslashes() {
        let toks = tokens("var pat = '\\s*'\n");

        assert_eq!(texts(&toks, TokKind::Str), vec!["'\\s*'"]);
    }

    #[test]
    fn a_doubled_quote_stays_inside_a_single_quoted_string() {
        let toks = tokens("var s = 'it''s'\n");

        assert_eq!(texts(&toks, TokKind::Str), vec!["'it''s'"]);
    }

    #[test]
    fn concat_is_one_operator_not_two_member_dots() {
        let toks = tokens("var s = PREFIX .. name\n");

        assert_eq!(texts(&toks, TokKind::Op), vec!["=", ".."]);
        assert_eq!(
            texts(&toks, TokKind::Ident),
            vec!["var", "s", "PREFIX", "name"]
        );
    }

    #[test]
    fn a_member_dot_stays_one_character() {
        let toks = tokens("Color.Red\n");

        assert_eq!(texts(&toks, TokKind::Op), vec!["."]);
    }

    #[test]
    fn a_backslash_continuation_joins_two_physical_lines() {
        let toks = tokens("var x = 1\n      \\ + 2\n");

        let kinds: Vec<TokKind> = toks.iter().map(|t| t.kind).collect();
        assert_eq!(
            kinds.iter().filter(|k| **k == TokKind::Newline).count(),
            1,
            "one statement, so one newline: {toks:?}"
        );
        assert_eq!(
            toks.iter()
                .find(|t| t.text == "2")
                .expect("the second operand")
                .line,
            2
        );
    }

    #[test]
    fn an_open_bracket_joins_two_physical_lines() {
        let toks = tokens("Call(\n  arg,\n)\n");

        assert_eq!(
            toks.iter().filter(|t| t.kind == TokKind::Newline).count(),
            1,
            "one statement, so one newline: {toks:?}"
        );
    }

    #[test]
    fn a_heredoc_body_is_not_tokenised_as_code() {
        let toks = tokens("var lines =<< trim END\n  def NotAFunction()\nEND\nvar y = 1\n");

        assert!(
            !texts(&toks, TokKind::Ident).contains(&"NotAFunction"),
            "the body is text, not code: {toks:?}"
        );
        assert!(
            texts(&toks, TokKind::Ident).contains(&"y"),
            "the code after the body still lexes"
        );
    }

    #[test]
    fn an_unterminated_string_ends_at_the_line() {
        let toks = tokens("echo 'open\nvar y = 1\n");

        assert!(texts(&toks, TokKind::Ident).contains(&"y"));
    }

    #[test]
    fn a_hash_inside_a_name_is_part_of_it() {
        let toks = tokens("call bartleby#Open()\n");

        assert!(
            texts(&toks, TokKind::Ident).contains(&"bartleby#Open"),
            "the autoload calling convention is one name: {toks:?}"
        );
        assert!(texts(&toks, TokKind::Comment).is_empty());
    }

    #[test]
    fn a_hash_after_a_space_still_opens_a_comment() {
        let toks = tokens("var x = 1 # why\n");

        assert_eq!(texts(&toks, TokKind::Comment), vec!["# why"]);
    }

    #[test]
    fn an_interpolated_string_lexes_its_braces_as_code() {
        let toks = tokens("echo $'count: {LABEL} done'\n");

        assert!(
            texts(&toks, TokKind::Ident).contains(&"LABEL"),
            "a brace in an interpolated string holds code: {toks:?}"
        );
    }

    #[test]
    fn an_interpolated_string_keeps_its_literal_text_out_of_the_code() {
        let toks = tokens("echo $'count: {LABEL} done'\n");

        assert!(
            !texts(&toks, TokKind::Ident).contains(&"count"),
            "the literal part is text: {toks:?}"
        );
    }

    #[test]
    fn an_interpolated_string_reads_a_call_inside_its_braces() {
        let toks = tokens("echo $'{Fmt(x)} done'\n");

        assert!(texts(&toks, TokKind::Ident).contains(&"Fmt"));
    }

    #[test]
    fn a_doubled_brace_in_an_interpolated_string_is_not_code() {
        let toks = tokens("echo $'{{literal}} done'\n");

        assert!(
            !texts(&toks, TokKind::Ident).contains(&"literal"),
            "a doubled brace escapes itself: {toks:?}"
        );
    }

    #[test]
    fn an_option_name_is_one_token() {
        let toks = tokens("if &cp\n");

        assert_eq!(texts(&toks, TokKind::Ident), vec!["if", "&cp"]);
    }

    #[test]
    fn an_environment_variable_and_a_register_are_tokens() {
        let toks = tokens("echo $HOME .. @a\n");

        assert_eq!(texts(&toks, TokKind::Ident), vec!["echo", "$HOME", "@a"]);
    }

    #[test]
    fn a_comparison_against_a_number_lexes_whole() {
        let toks = tokens("if v:version < 901 || &cp\n");

        assert_eq!(texts(&toks, TokKind::Num), vec!["901"]);
    }

    #[test]
    fn a_line_number_counts_physical_lines() {
        let toks = tokens("# one\n\ndef F()\n");

        assert_eq!(
            toks.iter().find(|t| t.text == "def").expect("the def").line,
            3
        );
    }

    #[test]
    fn a_token_that_touches_the_one_before_it_is_glued() {
        let toks = tokens("vim9script\nautocmd BufRead *.fountain setfiletype fountain\n");
        let at = |text: &str| toks.iter().position(|t| t.text == text).expect(text);

        assert!(toks[at("*") + 1].glued, "the dot touches the star");
        assert!(toks[at("*") + 2].glued, "fountain touches the dot");
        assert!(
            !toks[at("setfiletype")].glued,
            "a space stands before the body"
        );
    }

    #[test]
    fn the_first_token_of_a_line_is_not_glued() {
        let toks = tokens("vim9script\n  echo x\n");

        assert!(!toks.iter().find(|t| t.text == "echo").expect("echo").glued);
    }

    #[test]
    fn a_heredoc_body_carries_no_glued_token() {
        let toks = tokens("vim9script\nvar lines =<< END\n  *.c text\nEND\n");

        assert!(toks
            .iter()
            .filter(|t| t.kind == TokKind::Heredoc)
            .all(|t| !t.glued));
    }

    #[test]
    fn a_continued_line_starts_a_token_that_is_not_glued() {
        let toks = tokens("vim9script\ncommand! -bar\n  \\ Recover BA.Recover()\n");

        assert!(
            !toks
                .iter()
                .find(|t| t.text == "Recover")
                .expect("Recover")
                .glued
        );
    }

    /// A legacy script marks a comment with a double quote, so the
    /// line is no string and a name in it is no use of the name.
    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/60
    #[test]
    fn a_line_that_opens_with_a_quote_in_a_legacy_script_is_a_comment() {
        let toks = tokens("\" reads g:dead never\nlet g:dead = 1\n");

        assert_eq!(toks[0].kind, TokKind::Comment);
        assert!(toks.iter().all(|t| t.kind != TokKind::Str));
    }

    #[test]
    fn a_line_that_opens_with_a_quote_in_a_vim9_script_is_a_string() {
        let toks = tokens("vim9script\nvar l = [\n  \"a\",\n]\n");

        assert!(toks.iter().any(|t| t.kind == TokKind::Str));
    }

    /// Legacy script continues a line with a backslash alone, so this
    /// script is not valid. The rule is for a bracket that a fault of
    /// the script or of the lexer leaves open: the line stays a string
    /// there, which can hide a finding and cannot make a false one.
    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/78
    #[test]
    fn a_line_that_opens_with_a_quote_inside_brackets_is_a_string() {
        let toks = tokens("let l = [\n\"a\",\n]\n");

        assert!(toks.iter().any(|t| t.kind == TokKind::Str));
    }

    #[test]
    fn a_line_that_opens_with_a_quote_behind_vim9script_is_no_comment() {
        let toks = tokens("\" legacy\nvim9script\n\"a\"->F()\n");

        assert_eq!(toks.iter().filter(|t| t.kind == TokKind::Str).count(), 1);
    }

    /// FUNCTION: How many statements a snippet holds, and whether any
    /// token of it is a string.
    fn shape(text: &str) -> (usize, bool) {
        let toks = tokens(text);

        (
            toks.iter().filter(|t| t.kind == TokKind::Newline).count(),
            toks.iter().any(|t| t.kind == TokKind::Str),
        )
    }

    /// A legacy script writes a comment between the lines of a
    /// continued command as `"\ text`. The comment is no string, and
    /// the command goes on behind it.
    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/67
    #[test]
    fn a_legacy_comment_between_continued_lines_does_not_end_the_command() {
        assert_eq!(shape("echo 1\n  \"\\ g:dead\n  \\ + 2\n"), (1, false));
    }

    #[test]
    fn a_legacy_comment_between_continued_lines_inside_brackets_is_no_string() {
        assert_eq!(shape("let x = [1,\n  \"\\ g:dead\n  \\ 2]\n"), (1, false));
    }

    /// The keys of a mapping are read in a mode of their own, which
    /// the comment must leave as it found it.
    #[test]
    fn a_legacy_comment_between_the_lines_of_a_mapping_changes_no_token() {
        let read = |text: &str| -> Vec<(TokKind, String)> {
            tokens(text).into_iter().map(|t| (t.kind, t.text)).collect()
        };

        assert_eq!(
            read("nnoremap x\n  \"\\ g:dead\n  \\ :call F()<CR>\n"),
            read("nnoremap x\n  \\ :call F()<CR>\n")
        );
    }

    /// A `function` body is legacy script in a Vim9 script too.
    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/67
    #[test]
    fn a_line_that_opens_with_a_quote_in_a_function_of_a_vim9_script_is_a_comment() {
        let text = "vim9script\nfunction F()\n  \" reads g:dead\n  let g:dead = 1\nendfunction\n";

        assert!(!shape(text).1);
    }

    #[test]
    fn a_line_that_opens_with_a_quote_behind_a_function_of_a_vim9_script_is_a_string() {
        let text = "vim9script\nfunction F()\nendfunction\n\"a\"->G()\n";

        assert!(shape(text).1);
    }

    /// A `def` body is Vim9 in a legacy script.
    #[test]
    fn a_line_that_opens_with_a_quote_in_a_def_of_a_legacy_script_is_a_string() {
        let text = "def F()\n  \"a\"->G()\nenddef\n";

        assert!(shape(text).1);
    }

    /// `fu` abbreviates `function`, and it is a name a script can give
    /// a variable.
    #[test]
    fn a_variable_named_as_an_abbreviation_of_function_opens_no_body() {
        let text = "vim9script\nvar fu = 0\nfu = 1\n\"a\"->G()\n";

        assert!(shape(text).1);
    }
}
