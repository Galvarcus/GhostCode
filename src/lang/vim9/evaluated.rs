//! A string the `execute` family runs, read as the command line Vim
//! will run: which of its words are Vim's own, and where the reading
//! has to stop.
//!
//! License: GNU GPL 3.0

use std::collections::HashSet;

use super::autocmd;
use super::builtins;
use super::excmds;
use super::lex;
use super::lex::TokKind;
use super::parse;
use super::parse::identifiers;

/// What opens the interpolated part of a string, which is where the
/// text stops being known: `$'setlocal tw={x}'` is read to the brace
/// and no further.
const GAP: char = '{';

/// What closes the interpolated part of a string.
const CLOSE: char = '}';

/// What stands before an option, as in `&guifont`.
const OPTION: &str = "&";

/// What divides a scope from the name behind it, and a receiver from
/// its key.
const COLON: &str = ":";
const DOT: &str = ".";

/// What opens and closes key notation, and what joins its parts, as
/// in `<C-w>`.
const KEY_OPEN: &str = "<";
const KEY_CLOSE: &str = ">";
const KEY_JOIN: &str = "-";

/// What opens the arguments of a call.
const CALL: &str = "(";

/// What opens and closes an index.
const INDEX: &str = "[";
const INDEX_CLOSE: &str = "]";

/// One name of an executed text.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Word {
    pub name: String,
    /// Whether the word is Vim's own.
    pub vims: bool,
    /// The name before the dot, where the word stands behind one
    /// inside a gap. Such a word is a member or a key, and no bare
    /// name of the project.
    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/71
    pub recv: Option<String>,
}

impl Word {
    /// METHOD: A word that stands behind no dot.
    pub fn bare((name, vims): (String, bool)) -> Self {
        Self {
            name,
            vims,
            recv: None,
        }
    }
}

/// FUNCTION: Every name the argument holds, in order, each with
/// whether it is Vim's own word.
///
/// The reading by position stops at the first gap, because a word
/// after one stands at a position no one can know: in
/// `execute $'echo {x} edit'`, whether `edit` is a command depends on
/// what `x` left behind. A gap that opens the text is the exception,
/// because what stands before a command can stand only there. The
/// harvest does not stop there. Three symbols in the corpora are
/// credited only by text after a gap, so every name still comes back.
///
/// Past the gap a word is marked for one of two reasons. Its own
/// shape says it is Vim's, wherever it stands: see `loose_words`. Or
/// the command before the gap takes the rest of its line as text or
/// as keys, and the word is outside every gap and is not called, or
/// stands in a string inside a gap. A mark never takes a credit from
/// a symbol, so a wrong mark costs a count and no finding.
///
/// A word behind a dot inside a gap comes back with its receiver. The
/// gap is code, and the scan of the code has read the same word as a
/// member, so a bare name here would credit a function or a variable
/// of that spelling.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/71
pub fn names(arg: &str) -> Vec<Word> {
    let (head, tail) = arg.split_once(GAP).unwrap_or((arg, ""));
    let stmts = parse::statements(&lex::tokens(head));
    let mut owns = stmts.last().is_some_and(|stmt| parse::owns_line(stmt));

    let mut vims = vims_words(&stmts);
    vims.extend(loose_words(head, false));

    let mut out: Vec<Word> = identifiers(head)
        .into_iter()
        .map(|name| Word::bare((name.clone(), vims.contains(&name))))
        .collect();

    // The tail opens inside a gap, and the gaps and the text between
    // them take turns from there.
    let mut code = true;
    let mut rest = tail;

    // A gap that opens the text, alone or behind the colon and the
    // range of a command line, holds what stands before a command: the
    // start of its name, as `{mode}noremap`, or its modifiers and its
    // count, as `{mods} copen` and `:{bnum}bw`. The text behind that
    // gap is read by position as a head is.
    // REFERENCE: https://github.com/Galvarcus/GhostCode/issues/124
    let mut glued = lex::tokens(head)
        .iter()
        .all(|tok| tok.text == COLON || parse::in_range(&tok.text));

    while !rest.is_empty() {
        let end = if code { CLOSE } else { GAP };
        let (part, after) = rest.split_once(end).unwrap_or((rest, ""));
        let mut loose = loose_words(part, code);

        if !code && glued {
            let text = part.trim_start();

            if text.starts_with(|c: char| c.is_ascii_alphabetic()) {
                let stmts = parse::statements(&lex::tokens(text));

                owns = stmts.last().is_some_and(|stmt| parse::owns_line(stmt));
                loose.extend(vims_words(&stmts));
            }

            glued = false;
        }

        // A string inside a gap of a line that a command owns is text
        // that goes into that line, as the keyword of a menu command
        // is in `amenu {on ? "enable" : "disable"}`.
        if code && owns {
            loose.extend(string_words(part));
        }

        // A word that is called is a function, and one the shape
        // rules did not take is no builtin: it is the project's, as
        // the function a mapping runs is.
        let called = called_words(part);

        // The receivers are taken in order, one for each word the
        // tokens show behind a dot.
        let mut keys = if code { keyed(part) } else { Vec::new() };

        out.extend(identifiers(part).into_iter().map(|name| {
            let vims = (!code && owns && !called.contains(&name)) || loose.contains(&name);
            let recv = keys
                .iter()
                .position(|(key, _)| *key == name)
                .map(|at| keys.remove(at).1);

            Word { name, vims, recv }
        }));

        code = !code;
        rest = after;
    }

    out
}

/// FUNCTION: Every name an expression holds, in order, each with
/// whether its shape says it is Vim's own word.
///
/// `eval()` takes an expression, which has no command and no
/// position to read, so only the shape of a word marks it.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
pub fn loose(arg: &str) -> Vec<(String, bool)> {
    let vims = loose_words(arg, false);

    identifiers(arg)
        .into_iter()
        .map(|name| (name.clone(), vims.contains(&name)))
        .collect()
}

/// FUNCTION: The words of a readable head that Vim reads as its own: a
/// command at a head position, a modifier before one, a user command,
/// the arguments of a set-family command and of a command whose
/// arguments are Vim's own text, such as `:highlight`, the keys of a
/// mapping command, and what an autocommand states before the command
/// it runs.
///
/// The head is lexed and run through the statement rules, so a
/// command written short is read as one and a bar starts the next
/// command, exactly as in code.
///
/// A text holds a command line and nothing else, so a word of one
/// letter at a head position is a command, as the `b` of
/// `keepalt b`. The scope of `g:x` has its colon glued behind it. A
/// line Vim owns keeps the words of its strings as well, as the keys
/// `"_y` of a `:normal`, where the quote names a register.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/124
fn vims_words(stmts: &[Vec<lex::Tok>]) -> HashSet<String> {
    let mut out = HashSet::new();

    for stmt in stmts {
        let heads = parse::heads(stmt);
        let owned = parse::command_at(stmt).and_then(|at| autocmd::owned(stmt, at));

        if parse::owns_line(stmt) {
            out.extend(
                stmt.iter()
                    .filter(|tok| tok.kind == TokKind::Str)
                    .flat_map(|tok| identifiers(&tok.text)),
            );
        }

        for (i, tok) in stmt.iter().enumerate() {
            if tok.kind != TokKind::Ident {
                continue;
            }

            let scope = stmt
                .get(i + 1)
                .is_some_and(|next| next.text == COLON && next.glued);
            let word = tok.text.as_str();

            let vims = (parse::in_command(stmt, i, &heads)
                && (excmds::canonical(word).is_some()
                    || parse::user_command(word)
                    || (word.len() == 1 && !scope)))
                || parse::set_args(stmt, i, &heads)
                || parse::text_args(stmt, i, &heads)
                || parse::map_args(stmt, i)
                || parse::in_command_def(stmt, i)
                || owned.as_ref().is_some_and(|own| own.contains(&i));

            if vims {
                out.insert(tok.text.clone());
            }
        }
    }

    out
}

/// FUNCTION: The words of a text whose shape says they are Vim's own,
/// wherever they stand: a word of the language such as `true`, a
/// builtin that is called, an option behind its sigil, a scope letter
/// and the name behind it, and the parts of key notation.
///
/// `keys` adds the name behind a dot. Inside a gap the text is an
/// expression, which the lexer has read as code already, and there a
/// name behind a dot is a member or a key of a dictionary and no
/// name of its own.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
fn loose_words(text: &str, keys: bool) -> HashSet<String> {
    let toks = lex::tokens(text);

    // A word of the language goes by its spelling alone, so that one
    // inside a string of the text is taken as well.
    let mut out: HashSet<String> = identifiers(text)
        .into_iter()
        .filter(|name| parse::KEYWORDS.contains(&name.as_str()))
        .collect();

    let is = |at: usize, text: &str| toks.get(at).is_some_and(|t| t.text == text);
    let glued = |at: usize| toks.get(at).is_some_and(|t| t.glued);

    for (i, tok) in toks.iter().enumerate() {
        if tok.kind != TokKind::Ident {
            continue;
        }

        let word = tok.text.as_str();
        let behind = |text: &str| i > 0 && tok.glued && is(i - 1, text);

        let option = word.starts_with(OPTION) || behind(OPTION);
        let scope = parse::SCOPES.contains(&word) && is(i + 1, COLON) && glued(i + 1);
        let scoped = behind(COLON)
            && i > 1
            && glued(i - 1)
            && parse::SCOPES.contains(&toks[i - 2].text.as_str());
        let called = is(i + 1, CALL) && builtins::has(word);
        let key = keys && is_key(&toks, i);

        if option || scope || scoped || called || key || in_notation(&toks, i) {
            out.insert(word.trim_start_matches(OPTION).to_string());
        }
    }

    out
}

/// FUNCTION: Each word of a gap that stands behind a dot and a name,
/// with that name, as `Enabled` and `item` in `item.Enabled`.
fn keyed(text: &str) -> Vec<(String, String)> {
    let toks = lex::tokens(text);

    toks.iter()
        .enumerate()
        .filter(|(i, tok)| is_key(&toks, *i) && tok.kind == TokKind::Ident)
        .filter_map(|(i, tok)| Some((tok.text.clone(), receiver(&toks, i - 1)?)))
        .collect()
}

/// FUNCTION: Whether the token at `i` is glued behind a dot that
/// follows a name.
fn is_key(toks: &[lex::Tok], i: usize) -> bool {
    i > 1 && toks[i].glued && toks[i - 1].text == DOT && receiver(toks, i - 1).is_some()
}

/// FUNCTION: The name a dot at `dot` reaches into, past every index
/// behind that name, as the `t` of `t[0].file`.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/124
fn receiver(toks: &[lex::Tok], dot: usize) -> Option<String> {
    let mut k = dot.checked_sub(1)?;
    let mut depth = 0usize;

    loop {
        match toks[k].text.as_str() {
            INDEX_CLOSE => depth += 1,
            INDEX => depth = depth.checked_sub(1)?,
            _ if depth == 0 => break,
            _ => {}
        }

        k = k.checked_sub(1)?;
    }

    (toks[k].kind == TokKind::Ident).then(|| toks[k].text.clone())
}

/// FUNCTION: The words inside the strings of an expression.
fn string_words(text: &str) -> HashSet<String> {
    lex::tokens(text)
        .iter()
        .filter(|tok| tok.kind == TokKind::Str)
        .flat_map(|tok| identifiers(&tok.text))
        .collect()
}

/// FUNCTION: The words of a text that are called.
fn called_words(text: &str) -> HashSet<String> {
    let toks = lex::tokens(text);

    toks.iter()
        .enumerate()
        .filter(|(i, tok)| {
            tok.kind == TokKind::Ident && toks.get(i + 1).is_some_and(|next| next.text == CALL)
        })
        .map(|(_, tok)| tok.text.clone())
        .collect()
}

/// FUNCTION: Whether the word at `i` is a part of key notation: it
/// stands in an unbroken run of words and joins that opens with `<`
/// and closes with `>`, as `C` and `w` do in `<C-w>`.
fn in_notation(toks: &[lex::Tok], i: usize) -> bool {
    let part = |t: &lex::Tok| {
        t.glued && (t.kind == TokKind::Ident || t.kind == TokKind::Num || t.text == KEY_JOIN)
    };

    let open = (0..i)
        .rev()
        .find(|k| !part(&toks[*k]))
        .is_some_and(|k| toks[k].text == KEY_OPEN);

    let close = (i + 1..toks.len())
        .find(|k| !part(&toks[*k]))
        .is_some_and(|k| toks[k].glued && toks[k].text == KEY_CLOSE);

    open && toks[i].glued && close
}

#[cfg(test)]
mod tests {
    use super::names;
    use super::Word;

    /// FUNCTION: The names of an argument that are Vim's own word.
    fn words_of(arg: &str) -> Vec<String> {
        names(arg)
            .into_iter()
            .filter(|word| word.vims)
            .map(|word| word.name)
            .collect()
    }

    #[test]
    fn a_command_at_the_head_is_vims() {
        assert_eq!(words_of("silent echo x"), vec!["silent", "echo"]);
    }

    #[test]
    fn an_abbreviated_command_at_the_head_is_vims() {
        assert_eq!(words_of("sil! bwipe! 3"), vec!["sil", "bwipe"]);
    }

    #[test]
    fn every_name_of_the_argument_comes_back_in_order() {
        assert_eq!(
            names("silent echo x"),
            vec![
                Word::bare(("silent".to_string(), true)),
                Word::bare(("echo".to_string(), true)),
                Word::bare(("x".to_string(), false)),
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
            vec!["silent", "bwipe", "edit", "x"]
        );
    }

    #[test]
    fn an_argument_that_is_no_command_is_left_alone() {
        assert_eq!(words_of("echo Foo"), vec!["echo"]);
    }

    #[test]
    fn the_arguments_of_a_highlight_command_are_vims() {
        assert_eq!(
            words_of("highlight link Foo Normal"),
            vec!["highlight", "link", "Foo", "Normal"]
        );
    }

    #[test]
    fn a_name_after_a_gap_inside_the_text_is_never_vims() {
        assert_eq!(words_of("echo {x} edit"), vec!["echo"]);
    }

    #[test]
    fn a_user_command_at_the_head_is_vims() {
        assert_eq!(words_of("PluginOpen draft"), vec!["PluginOpen", "draft"]);
    }

    #[test]
    fn a_user_command_behind_a_modifier_is_vims() {
        assert_eq!(words_of("silent! PluginOpen"), vec!["silent", "PluginOpen"]);
    }

    #[test]
    fn the_keys_of_a_mapping_command_are_vims() {
        assert_eq!(
            words_of("nnoremap <silent> <C-w>"),
            vec!["nnoremap", "silent", "C", "w"]
        );
    }

    #[test]
    fn the_event_and_the_flags_of_an_autocommand_are_vims() {
        assert_eq!(
            words_of("autocmd WinEnter,CursorMoved <buffer> ++nested Run()"),
            vec!["autocmd", "WinEnter", "CursorMoved", "buffer", "nested"]
        );
    }

    #[test]
    fn the_event_a_doautocmd_names_is_vims() {
        assert_eq!(
            words_of("doautocmd <nomodeline> User "),
            vec!["doautocmd", "nomodeline", "User"]
        );
    }

    #[test]
    fn an_option_behind_its_sigil_is_vims() {
        assert_eq!(words_of("&guifont = Font"), vec!["guifont"]);
    }

    #[test]
    fn a_literal_of_the_language_is_vims() {
        assert_eq!(words_of("&fullscreen = true"), vec!["fullscreen", "true"]);
    }

    #[test]
    fn a_scope_letter_and_the_name_behind_it_are_vims() {
        assert_eq!(words_of("echo t:session"), vec!["echo", "t", "session"]);
    }

    #[test]
    fn a_builtin_called_past_a_gap_is_vims() {
        assert_eq!(words_of("{x} {string(c)}"), vec!["string"]);
    }

    #[test]
    fn a_function_of_the_project_called_past_a_gap_is_not_vims() {
        assert_eq!(words_of("{x} {Width(c)}"), Vec::<String>::new());
    }

    #[test]
    fn key_notation_past_a_gap_is_vims() {
        assert_eq!(
            words_of("{m} <silent> <Plug>({name}) <C-g>"),
            vec!["silent", "Plug", "C", "g"]
        );
    }

    #[test]
    fn a_key_read_from_a_dictionary_inside_a_gap_is_vims() {
        assert_eq!(words_of("{x} {saved.font}"), vec!["font"]);
    }

    /// A command whose arguments are text to the end of the line owns
    /// the literal words past a gap as well, whatever the gap holds.
    #[test]
    fn the_text_past_a_gap_of_a_highlight_command_is_vims() {
        assert_eq!(
            words_of("highlight {grp} ctermfg={Color(n)} guisp=bg"),
            vec!["highlight", "ctermfg", "guisp", "bg"]
        );
    }

    #[test]
    fn the_keys_past_a_gap_of_a_mapping_command_are_vims() {
        assert_eq!(
            words_of("inoremap <buffer> {ch} {ch}u"),
            vec!["inoremap", "buffer", "u"]
        );
    }

    #[test]
    fn the_text_past_a_gap_of_a_menu_command_is_vims() {
        assert_eq!(
            words_of("amenu {priority} {path} <Cmd>call Run()<CR>"),
            vec!["amenu", "Cmd", "call", "CR"]
        );
    }

    #[test]
    fn the_unit_of_a_sleep_command_is_vims() {
        assert_eq!(words_of("sleep {ms}m"), vec!["sleep", "m"]);
    }

    #[test]
    fn the_flags_of_a_vimgrep_command_are_vims() {
        assert_eq!(
            words_of("silent! vimgrep /{pat}/j {files}"),
            vec!["silent", "vimgrep", "j"]
        );
    }

    #[test]
    fn the_text_past_a_gap_of_a_set_command_is_not_vims() {
        assert_eq!(words_of("setlocal tw={x} Later"), vec!["setlocal", "tw"]);
    }

    #[test]
    fn an_expression_keeps_its_names_and_marks_its_option() {
        assert_eq!(
            super::loose("&guifont .. Suffix"),
            vec![("guifont".to_string(), true), ("Suffix".to_string(), false),]
        );
    }

    /// A string inside a gap is text of the expression, and a word of
    /// the language in it can still be no name of the project.
    #[test]
    fn a_literal_of_the_language_in_a_string_inside_a_gap_is_vims() {
        assert_eq!(
            words_of("&fullscreen = {on ? \"true\" : \"false\"}"),
            vec!["fullscreen", "true", "false"]
        );
    }

    /// A word glued behind the gap that opens the text is the rest of
    /// a command the gap began, as the mode letter of a mapping
    /// command is put before `noremap`.
    #[test]
    fn a_command_glued_behind_the_gap_that_opens_the_text_is_vims() {
        assert_eq!(
            words_of("{m}noremap <silent> <Plug>({name}) {rhs}"),
            vec!["noremap", "silent", "Plug"]
        );
    }

    #[test]
    fn the_keys_behind_a_command_glued_to_the_opening_gap_are_vims() {
        assert_eq!(words_of("{m}map {lhs} x"), vec!["map", "x"]);
    }

    /// The gap that opens the text holds what stands before a command,
    /// as modifiers or a count, so the word apart from it is read by
    /// position too.
    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/124
    #[test]
    fn a_command_apart_from_the_gap_that_opens_the_text_is_vims() {
        assert_eq!(words_of("{mods} copen"), vec!["copen"]);
    }

    #[test]
    fn a_command_behind_a_range_and_a_gap_is_vims() {
        assert_eq!(words_of(":{bnum}bw"), vec!["bw"]);
    }

    #[test]
    fn the_attributes_of_a_command_definition_are_vims() {
        assert_eq!(
            words_of("command -nargs=* -bang -range"),
            vec!["command", "nargs", "bang", "range"]
        );
    }

    #[test]
    fn the_keys_in_a_string_of_a_normal_command_are_vims() {
        assert_eq!(words_of("normal! 1G\"_y"), vec!["normal", "_y"]);
    }

    #[test]
    fn a_command_of_one_letter_behind_a_modifier_is_vims() {
        assert_eq!(words_of("sil! keepalt b "), vec!["sil", "keepalt", "b"]);
    }

    #[test]
    fn a_word_behind_an_index_inside_a_gap_is_a_member() {
        let file = names("split {t[0].file}")
            .into_iter()
            .find(|word| word.name == "file")
            .expect("the word comes back");

        assert_eq!(file.recv.as_deref(), Some("t"));
    }

    /// A string inside a gap of a line that a command owns is text
    /// that goes into that line.
    #[test]
    fn a_string_inside_a_gap_of_a_menu_command_is_vims() {
        assert_eq!(
            words_of("amenu {on ? \"enable\" : \"disable\"} {path}"),
            vec!["amenu", "enable", "disable"]
        );
    }

    #[test]
    fn a_string_inside_a_gap_of_a_command_that_owns_no_line_is_not_vims() {
        assert_eq!(
            words_of("echo {on ? \"enable\" : \"disable\"}"),
            vec!["echo"]
        );
    }

    /// `:source` takes a file name to the end of its line.
    #[test]
    fn the_file_a_source_command_names_is_vims() {
        assert_eq!(
            words_of("source {expand('<sfile>:h:h')}/plugin/logger.vim"),
            vec!["source", "expand", "sfile", "h", "h", "plugin", "logger", "vim"]
        );
    }
}
