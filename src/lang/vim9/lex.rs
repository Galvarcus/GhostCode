//! The Vim9 lexer: source text to tokens, with physical line numbers.
//!
//! License: GNU GPL 3.0

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
}

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
                });
            }
            continue;
        }

        let mut rest = raw.trim_start();

        // A line that opens with a backslash, or with an arrow, carries
        // the line before it on, so the statement did not end there.
        if rest.starts_with('\\') {
            rest = &rest[1..];
            pop_newline(&mut toks);
        } else if rest.starts_with("->") || rest.starts_with("|") {
            pop_newline(&mut toks);
        }

        lex_line(rest, line, &mut toks, &mut depth, &mut heredoc);

        // Inside brackets the statement continues on the next line.
        if depth <= 0 {
            depth = 0;
            push_newline(&mut toks, line);
        }
    }

    push_newline(&mut toks, text.lines().count() as u32);
    toks
}

/// FUNCTION: Tokenise one logical line's worth of text.
fn lex_line(
    text: &str,
    line: u32,
    toks: &mut Vec<Tok>,
    depth: &mut i32,
    heredoc: &mut Option<String>,
) {
    let src: Vec<char> = text.chars().collect();
    let mut i = 0;
    let mut heredoc_here = false;

    while i < src.len() {
        let c = src[i];

        if c.is_whitespace() {
            i += 1;
            continue;
        }

        // A comment runs to the end of the line. In Vim9 that is `#`
        // alone: a double quote opens a string.
        if c == '#' {
            toks.push(Tok {
                kind: TokKind::Comment,
                text: src[i..].iter().collect(),
                line,
            });
            break;
        }

        if c == '\'' || c == '"' {
            let (text, next) = lex_str(&src, i, c);
            toks.push(Tok {
                kind: TokKind::Str,
                text,
                line,
            });
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
            toks.push(Tok {
                kind: TokKind::Num,
                text: src[start..i].iter().collect(),
                line,
            });
            continue;
        }

        if is_ident_start(c) {
            let start = i;
            while i < src.len() && is_ident(src[i]) {
                i += 1;
            }
            toks.push(Tok {
                kind: TokKind::Ident,
                text: src[start..i].iter().collect(),
                line,
            });
            continue;
        }

        if let Some(op) = op_at(&src, i) {
            if op == "=<<" {
                heredoc_here = true;
            }
            i += op.chars().count();
            toks.push(Tok {
                kind: TokKind::Op,
                text: op.to_string(),
                line,
            });
            continue;
        }

        match c {
            '(' | '[' | '{' => *depth += 1,
            ')' | ']' | '}' => *depth -= 1,
            _ => {}
        }

        let kind = match c {
            '(' | ')' | '[' | ']' | '{' | '}' | ',' | ';' | ':' => TokKind::Punct,
            _ => TokKind::Op,
        };
        toks.push(Tok {
            kind,
            text: c.to_string(),
            line,
        });
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
    c.is_ascii_alphabetic() || c == '_' || c == '&' || c == '$' || c == '@'
}

// A scope prefix such as `g:` is three tokens, not one, because Vim9
// writes a type annotation as `x: Foo` with the colon against the name,
// and an identifier that swallowed a colon would swallow that too.
fn is_ident(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '_'
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
    fn a_line_number_counts_physical_lines() {
        let toks = tokens("# one\n\ndef F()\n");

        assert_eq!(
            toks.iter().find(|t| t.text == "def").expect("the def").line,
            3
        );
    }
}
