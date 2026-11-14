//! The Vim9 parser: statements to declarations.
//!
//! License: GNU GPL 3.0

use std::ops::Range;
use std::path::Component;
use std::path::Path;
use std::path::PathBuf;

use crate::lang::vim9::autocmd;
use crate::lang::vim9::builtins;
use crate::lang::vim9::evaluated;
use crate::lang::vim9::evaluated::Word;
use crate::lang::vim9::excmds;
use crate::lang::vim9::exists;
use crate::lang::vim9::lex::Tok;
use crate::lang::vim9::lex::TokKind;
use crate::lang::vim9::rules;
use crate::lang::vim9::shared;
use crate::lang::vim9::types;
use crate::lang::vim9::types::Blocks;
use crate::lang::vim9::types::Locals;
use crate::lang::vim9::types::Types;
use crate::model::Fit;
use crate::model::Import;
use crate::model::Kind;
use crate::model::Reference;
use crate::model::Sink;
use crate::model::Symbol;
use crate::model::SymbolId;
use crate::model::Text;

// A modifier that may stand before a declaration and says nothing
// about what is declared.
const MODIFIERS: &[&str] = &[
    "static",
    "public",
    "protected",
    "private",
    "abstract",
    "final",
];

/// What encloses a statement: a class, an enum, an interface, or the
/// file itself.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
enum Container {
    #[default]
    None,
    Class,
    Enum,
    Interface,
}

/// Where the parser is: inside which container, and inside a function
/// body or not. A declaration inside a body is a local, which the
/// analyzer does not report.
#[derive(Debug, Clone, Default)]
pub struct Scope {
    owner: Option<String>,
    owner_exported: bool,
    container: Container,
    /// The function bodies enclosing the statement, innermost last.
    /// Vim9 allows a def inside a def, so one `enddef` closes one
    /// body and not the one around it, and a counter cannot say which
    /// body the statements after the inner `enddef` belong to.
    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
    bodies: Vec<SymbolId>,
}

impl Scope {
    /// METHOD: The body a statement sits in, innermost first, or none
    /// at the top level of the file.
    fn body(&self) -> Option<&SymbolId> {
        self.bodies.last()
    }

    /// METHOD: How many bodies enclose the statement. A declaration is
    /// a local while this is above zero.
    fn depth(&self) -> usize {
        self.bodies.len()
    }
}

/// FUNCTION: Split a file's tokens into statements, dropping comments
/// and heredoc bodies, which declare nothing. The lexer has already
/// joined a continued line to the statement it belongs to.
pub fn statements(toks: &[Tok]) -> Vec<Vec<Tok>> {
    let mut out: Vec<Vec<Tok>> = Vec::new();
    let mut cur: Vec<Tok> = Vec::new();

    for tok in toks {
        match tok.kind {
            TokKind::Newline => {
                if !cur.is_empty() {
                    out.push(std::mem::take(&mut cur));
                }
            }
            TokKind::Comment | TokKind::Heredoc => {}
            _ => cur.push(tok.clone()),
        }
    }

    if !cur.is_empty() {
        out.push(cur);
    }

    out
}

/// FUNCTION: Record every class, enum, interface, function, method,
/// field, enum value, and script variable that a file declares.
///
/// A statement the grammar does not recognise is passed over, so that
/// a legacy script, or one broken line, costs its own statement rather
/// than the rest of the file.
pub fn declarations(file: &Path, stmts: &[Vec<Tok>], out: &mut dyn Sink) {
    let mut scope = Scope::default();
    let consts = shared::consts(stmts);

    for stmt in stmts {
        let words: Vec<&str> = stmt
            .iter()
            .filter(|t| t.kind == TokKind::Ident)
            .map(|t| t.text.as_str())
            .collect();

        let Some(line) = stmt.first().map(|t| t.line) else {
            continue;
        };

        shared_writes(file, stmt, &consts, out);

        if close_container(&words, &mut scope) {
            continue;
        }

        if open_container(file, &words, line, &mut scope, out) {
            continue;
        }

        if function(file, stmt, &words, line, &scope, out) {
            if let Some(id) = body_id(file, stmt, &words, &scope) {
                scope.bodies.push(id);
            }

            continue;
        }

        // A declaration inside a function body is a local, which is
        // a symbol of that body and of nothing wider.
        // REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
        if scope.depth() > 0 {
            local(file, stmt, &words, line, &scope, out);
            continue;
        }

        if scope.container == Container::Enum {
            enum_values(file, stmt, line, &scope, out);
            continue;
        }

        if alias(file, stmt, &words, line, &scope, out) {
            continue;
        }

        variable(file, stmt, &words, line, &scope, out);
    }
}

/// FUNCTION: Record each line of a heredoc body as text, and each
/// scoped variable it spells in full.
///
/// A statement holds no heredoc body, because the body is text and no
/// code. The text is often code that a plugin runs later, through an
/// autocommand or execute(), or a script for another Vim, so a name it
/// holds is in use, as a name a string holds is. The read is given to
/// the top-level code of the file: the lexer does not say which body a
/// heredoc stands in, and that code runs wherever any part of the file
/// does.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/55
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/87
pub fn heredocs(file: &Path, toks: &[Tok], out: &mut dyn Sink) {
    let origin = SymbolId::script(file);

    for tok in toks.iter().filter(|t| t.kind == TokKind::Heredoc) {
        out.text(Text {
            text: tok.text.clone(),
            file: file.to_path_buf(),
            line: tok.line,
            origin: Some(origin.clone()),
        });

        for name in shared::scope_givers(&tok.text) {
            out.give(name);
        }

        for spelling in shared::spellings(&tok.text) {
            match spelling {
                shared::Spelling::Exact(name) => out.re(Reference {
                    name,
                    recv: None,
                    file: file.to_path_buf(),
                    line: tok.line,
                    origin: Some(origin.clone()),
                    target: None,
                    owned: true,
                    member: false,
                }),
                shared::Spelling::Fit {
                    head,
                    tail,
                    whole,
                    needs,
                } => out.fit(Fit {
                    head,
                    tail,
                    whole,
                    needs: needs.map(str::to_string),
                    file: file.to_path_buf(),
                    line: tok.line,
                    origin: Some(origin.clone()),
                }),
            }
        }
    }
}

/// FUNCTION: Record each write of a variable every file shares, as a
/// declaration of it.
///
/// The variable is one for the project, so its id names no file, and
/// each write of it gives the same id. The report keeps one of them.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/55
fn shared_writes(file: &Path, stmt: &[Tok], consts: &shared::Consts, out: &mut dyn Sink) {
    for used in shared::uses(stmt, consts).found {
        let shared::Spelling::Exact(name) = used.spelling else {
            continue;
        };

        if !used.write {
            continue;
        }

        out.sym(Symbol {
            id: SymbolId::shared(&name),
            kind: Kind::Variable,
            name,
            file: file.to_path_buf(),
            line: stmt[used.at].line,
            exported: false,
            owner: None,
            scope: None,
            lead: used.lead,
        });
    }
}

/// FUNCTION: Open a class, enum, or interface. True when the statement
/// was one.
fn open_container(
    file: &Path,
    words: &[&str],
    line: u32,
    scope: &mut Scope,
    out: &mut dyn Sink,
) -> bool {
    let (exported, rest) = strip_export(words);
    let rest = strip_modifiers(rest);

    let Some((container, name)) = container_name(rest) else {
        return false;
    };

    let kind = match container {
        Container::Class => Kind::Class,
        Container::Enum => Kind::Enum,
        Container::Interface => Kind::Interface,
        Container::None => return false,
    };

    if let Some(base) = base_name(rest) {
        out.heir(name, base);
    }

    scope.owner = Some(name.to_string());
    scope.owner_exported = exported;
    scope.container = container;
    scope.bodies.clear();

    out.sym(Symbol {
        id: SymbolId::of(file, None, name),
        kind,
        name: name.to_string(),
        file: file.to_path_buf(),
        line,
        exported,
        owner: None,
        scope: None,
        lead: false,
    });

    true
}

/// FUNCTION: Close a container or a function body. True when the
/// statement was an `end` of either.
fn close_container(words: &[&str], scope: &mut Scope) -> bool {
    match words.first().copied() {
        Some("endclass" | "endenum" | "endinterface") => {
            *scope = Scope::default();
            true
        }
        Some("enddef") => {
            scope.bodies.pop();
            true
        }
        _ => false,
    }
}

/// FUNCTION: Record a `def`. True when the statement was one.
///
/// A signature in an interface declares nothing: it has no body, and
/// the classes that implement it carry the methods.
fn function(
    file: &Path,
    stmt: &[Tok],
    words: &[&str],
    line: u32,
    scope: &Scope,
    out: &mut dyn Sink,
) -> bool {
    let (exported, rest) = strip_export(words);
    let rest = strip_modifiers(rest);

    if rest.first().copied() != Some("def") {
        return false;
    }

    let Some(name) = def_name(stmt, rest) else {
        return false;
    };
    let name = &name;

    // A def's name is followed by its parameter list. Without one the
    // statement is not a declaration the analyzer can trust.
    if !stmt.iter().any(|t| t.text == "(") {
        return false;
    }

    if scope.container == Container::Interface {
        return true;
    }

    // Any user or plugin can call a global function, as it can an
    // export, so it is public API on the same terms.
    // REFERENCE: https://github.com/Galvarcus/GhostCode/issues/102
    let exported = exported || def_global(stmt, rest);
    let (kind, exported) = member_kind(scope, Kind::Function, Kind::Method, name, exported);
    let id = SymbolId::of(file, scope.owner.as_deref(), name);

    // A runner calls a test by its name, which no parser sees.
    // REFERENCE: https://github.com/Galvarcus/GhostCode/issues/101
    if rules::is_test(file, scope.owner.as_deref(), name) {
        out.root(id.clone());
    }

    out.sym(Symbol {
        id,
        kind,
        name: (*name).to_string(),
        file: file.to_path_buf(),
        line,
        exported,
        owner: scope.owner.clone(),
        scope: None,
        lead: false,
    });

    true
}

/// FUNCTION: Record a type alias, `type Name = list<string>`. True
/// when the statement was one. Vim takes one only at script level.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/88
fn alias(
    file: &Path,
    stmt: &[Tok],
    words: &[&str],
    line: u32,
    scope: &Scope,
    out: &mut dyn Sink,
) -> bool {
    if scope.owner.is_some() {
        return false;
    }

    let (exported, _) = strip_export(words);

    let Some(at) = alias_at(stmt) else {
        return false;
    };

    out.sym(Symbol {
        id: SymbolId::of(file, None, &stmt[at].text),
        kind: Kind::Type,
        name: stmt[at].text.clone(),
        file: file.to_path_buf(),
        line,
        exported,
        owner: None,
        scope: None,
        lead: false,
    });

    true
}

/// FUNCTION: Record a `var`, `const`, or `final`: a script variable at
/// module level, or a field inside a class.
fn variable(
    file: &Path,
    stmt: &[Tok],
    words: &[&str],
    line: u32,
    scope: &Scope,
    out: &mut dyn Sink,
) {
    let (exported, rest) = strip_export(words);
    let rest = strip_modifiers(rest);

    if !matches!(rest.first().copied(), Some("var" | "const")) {
        return;
    }

    for name in declared_names(stmt, rest) {
        if name == DISCARD {
            continue;
        }

        let (kind, exported) = member_kind(scope, Kind::Variable, Kind::Field, name, exported);

        out.sym(Symbol {
            id: SymbolId::of(file, scope.owner.as_deref(), name),
            kind,
            name: name.to_string(),
            file: file.to_path_buf(),
            line,
            exported,
            owner: scope.owner.clone(),
            scope: None,
            lead: false,
        });
    }
}

/// FUNCTION: The names a `var` or `const` statement declares: every
/// name in the brackets of one that unpacks a list, and otherwise the
/// one name after the declaring word.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
fn declared_names<'a>(stmt: &'a [Tok], rest: &[&'a str]) -> Vec<&'a str> {
    let unpacked = types::unpacked_at(stmt);

    if unpacked.is_empty() {
        return rest.get(1).copied().into_iter().collect();
    }

    unpacked.iter().map(|&at| stmt[at].text.as_str()).collect()
}

/// FUNCTION: Record a `var` or `const` inside a function body, scoped
/// to that body.
///
/// The declaring words are those `variable` accepts at module level,
/// so the same statement is not read differently one scope out. The
/// discard placeholder declares nothing worth recording.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
fn local(file: &Path, stmt: &[Tok], words: &[&str], line: u32, scope: &Scope, out: &mut dyn Sink) {
    let Some(body) = scope.body() else {
        return;
    };

    let (_, rest) = strip_export(words);
    let rest = strip_modifiers(rest);

    if !matches!(rest.first().copied(), Some("var" | "const")) {
        return;
    }

    for name in declared_names(stmt, rest) {
        // A name the language owns is dropped wherever it stands, so
        // no read of this variable ever reaches the reference list
        // and the analyzer cannot know whether it is used. Recording
        // it would make a finding of `var set = {}` read on the next
        // line.
        // REFERENCE: https://github.com/Galvarcus/GhostCode/issues/31
        if name == DISCARD || KEYWORDS.contains(&name) {
            continue;
        }

        out.sym(Symbol {
            id: SymbolId::in_scope(body, name),
            kind: Kind::Variable,
            name: name.to_string(),
            file: file.to_path_buf(),
            line,
            exported: false,
            owner: scope.owner.clone(),
            scope: Some(body.clone()),
            lead: false,
        });
    }
}

/// FUNCTION: Record the values an enum lists, which arrive several to
/// a line, with or without arguments: `Red, Green` and `Blue('b')`.
fn enum_values(file: &Path, stmt: &[Tok], line: u32, scope: &Scope, out: &mut dyn Sink) {
    for at in enum_values_at(stmt) {
        let tok = &stmt[at];

        out.sym(Symbol {
            id: SymbolId::of(file, scope.owner.as_deref(), &tok.text),
            kind: Kind::EnumValue,
            name: tok.text.clone(),
            file: file.to_path_buf(),
            line,
            exported: false,
            owner: scope.owner.clone(),
            scope: None,
            lead: false,
        });
    }
}

/// FUNCTION: Where each value of an enum body's line stands, so that
/// the walk which records them and the walk which reads references
/// agree on which names the line declares.
///
/// The second walk needs it because a declaration is not a use of
/// itself. Every other declaration states a keyword, and the name
/// after it is skipped; a value states nothing, so the line looked
/// like a use of each value it declared, and every value credited
/// itself.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/23
fn enum_values_at(stmt: &[Tok]) -> Vec<usize> {
    let mut out = Vec::new();
    let mut depth = 0i32;
    let mut want = true;

    for (at, tok) in stmt.iter().enumerate() {
        match tok.text.as_str() {
            "(" | "[" | "{" => depth += 1,
            ")" | "]" | "}" => depth -= 1,
            "," if depth == 0 => want = true,
            _ => {
                if want && depth == 0 && tok.kind == TokKind::Ident {
                    out.push(at);
                }
                want = false;
            }
        }
    }

    out
}

/// FUNCTION: Whether a declaration is a member of its container, and
/// whether it is exported.
///
/// Vim9 cannot export a member by itself, only the class, so a member
/// of an exported class is exported unless its name opens with an
/// underscore, which is the language's convention for private.
fn member_kind(
    scope: &Scope,
    free: Kind,
    member: Kind,
    name: &str,
    exported: bool,
) -> (Kind, bool) {
    match scope.owner {
        None => (free, exported),
        Some(_) => (member, scope.owner_exported && !name.starts_with('_')),
    }
}

/// FUNCTION: Take an `export` prefix off a statement's words.
fn strip_export<'a>(words: &'a [&'a str]) -> (bool, &'a [&'a str]) {
    match words.split_first() {
        Some((first, rest)) if *first == "export" => (true, rest),
        _ => (false, words),
    }
}

/// FUNCTION: Take any modifiers off a statement's words.
fn strip_modifiers<'a>(mut words: &'a [&'a str]) -> &'a [&'a str] {
    while let Some((first, rest)) = words.split_first() {
        if MODIFIERS.contains(first) {
            words = rest;
        } else {
            break;
        }
    }
    words
}

/// FUNCTION: Record every import a file states, with the file it names
/// and the names it binds.
///
/// The path is computed, not looked up: an import resolves to a path
/// relative to the project root, and the driver keeps the import only
/// when that path is one of the project's own sources. So a target
/// that git ignores, or that lies outside the root, resolves to
/// nothing here and is dropped there.
pub fn imports(file: &Path, stmts: &[Vec<Tok>], out: &mut dyn Sink) {
    for stmt in stmts {
        if stmt.first().map(|t| t.text.as_str()) != Some("import") {
            continue;
        }

        let Some(spec) = stmt.iter().find(|t| t.kind == TokKind::Str) else {
            continue;
        };
        let spec = unquote(&spec.text);

        // `import autoload 'foo.vim'` reads autoload/foo.vim, while
        // `import 'foo.vim'` reads import/foo.vim. Vim searches every
        // runtimepath entry for the second; one project root is the
        // case that matters here.
        let autoload = stmt.get(1).is_some_and(|t| t.text == "autoload");

        let Some(to) = resolve(file, &spec, autoload) else {
            continue;
        };

        out.import(Import {
            from: file.to_path_buf(),
            to,
            alias: Some(alias_of(stmt, &spec)),
            names: names_of(stmt),
        });
    }
}

/// FUNCTION: The path an import names, relative to the project root,
/// or none when it names a file outside it.
fn resolve(file: &Path, spec: &str, autoload: bool) -> Option<PathBuf> {
    let joined = if spec.starts_with("./") || spec.starts_with("../") || spec.starts_with('/') {
        file.parent()?.join(spec.trim_start_matches('/'))
    } else if autoload {
        Path::new("autoload").join(spec)
    } else {
        Path::new("import").join(spec)
    };

    simplify(&joined)
}

/// FUNCTION: Resolve `.` and `..` in a path without touching the
/// filesystem. A path that climbs above the root is not the project's,
/// and so is none.
fn simplify(path: &Path) -> Option<PathBuf> {
    let mut parts: Vec<std::ffi::OsString> = Vec::new();

    for part in path.components() {
        match part {
            Component::CurDir => {}
            Component::ParentDir => {
                parts.pop()?;
            }
            Component::Normal(p) => parts.push(p.to_os_string()),
            Component::RootDir | Component::Prefix(_) => return None,
        }
    }

    if parts.is_empty() {
        return None;
    }

    Some(parts.iter().collect())
}

/// FUNCTION: The namespace an import binds: the name after `as`, or
/// the target's own file stem.
fn alias_of(stmt: &[Tok], spec: &str) -> String {
    if let Some(i) = stmt.iter().position(|t| t.text == "as") {
        if let Some(name) = stmt.get(i + 1) {
            return name.text.clone();
        }
    }

    Path::new(spec)
        .file_stem()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_default()
}

/// FUNCTION: The names of `import {A, B as C} from ...`, each as the
/// pair this file calls it by and the name it really has.
fn names_of(stmt: &[Tok]) -> Vec<(String, String)> {
    let Some(open) = stmt.iter().position(|t| t.text == "{") else {
        return Vec::new();
    };
    let Some(close) = stmt.iter().position(|t| t.text == "}") else {
        return Vec::new();
    };

    let mut out: Vec<(String, String)> = Vec::new();

    for item in stmt[open + 1..close].split(|t| t.text == ",") {
        let words: Vec<&str> = item
            .iter()
            .filter(|t| t.kind == TokKind::Ident)
            .map(|t| t.text.as_str())
            .collect();

        match words.as_slice() {
            [name] => out.push(((*name).to_string(), (*name).to_string())),
            [orig, "as", alias] => out.push(((*alias).to_string(), (*orig).to_string())),
            _ => {}
        }
    }

    out
}

/// FUNCTION: Take the quotes off a string literal.
fn unquote(text: &str) -> String {
    let mut chars = text.chars();
    chars.next();
    chars.next_back();
    chars.collect()
}

// The language's own words, dropped wherever they stand.
//
// Vim9 refuses a declaration called `this`, `super`, `true`, `false`
// or `null`, so those five can never be a project's name. Every other
// word here is one Vim accepts as a variable name, and three reasons
// keep them.
//
// The declaration words stand in the middle of a statement, as the
// second word of `export def` or `public var`, where no
// statement-position rule reaches them. The operators `in`, `is`, `as`
// and `autoload` have no such rule at all. The rest, from `if` to
// `endfunction`, Vim reads at the head of a statement alone, so
// `in_command` could answer them, and they stay only because no
// measured project names a variable after one: a reference restored
// for nothing can credit a symbol that nothing else credits.
//
// The command words a project may reasonably use as a name are not
// here. `set`, `command`, `normal`, `echo` and their kin left, because
// dropping one wherever it stood cost a real project every read of
// `var set: dict<bool>`, and `in_command` suppresses Vim's own use.
//
// What the list must never hold is a word Vim9 does not have at all,
// because that costs a project a name of its own for nothing.
// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/28
// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/31
pub(super) const KEYWORDS: &[&str] = &[
    "vim9script",
    "def",
    "enddef",
    "class",
    "endclass",
    "extends",
    "implements",
    "endenum",
    "interface",
    "endinterface",
    "enum",
    "export",
    "import",
    "as",
    "autoload",
    "var",
    "const",
    "final",
    "static",
    "public",
    "protected",
    "private",
    "abstract",
    "this",
    "super",
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
    "throw",
    "return",
    "break",
    "continue",
    "in",
    // Vim9 compares identity with a word. The `?` forms need no entry,
    // because their mark is punctuation, while the `#` forms do: the
    // lexer lets a name hold a `#` so that `plugin#Func` stays whole.
    "is",
    "is#",
    "isnot",
    "isnot#",
    "true",
    "false",
    "null",
    "function",
    "endfunction",
];

// The assignments that write a variable without reading it first.
// `=` is the plain one and `=<<` opens a heredoc, which the lexer
// keeps whole. Every other assignment Vim9 has is compound: `n += 1`
// reads `n` before it writes it, so it is a read, and `n += 1` and
// `n = n + 1` must not give different answers for one statement
// spelled two ways.
// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
const WRITES: &[&str] = &["=", "=<<"];

// Vim9's discard placeholder. A value assigned to it is stated to be
// unwanted, so there is nothing to report and nothing to record.
// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
const DISCARD: &str = "_";

// What stands between a receiver and its member. A concatenation is
// `..`, which the lexer reads as one operator of its own.
// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
const DOT: &str = ".";

/// The words that open a type alias, `export type Name = ...`.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/88
const EXPORT: &str = "export";
const ALIAS: &str = "type";

/// The word before the class that a class extends, and the word that
/// ends that name where the class also implements an interface.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/82
const EXTENDS: &str = "extends";
const IMPLEMENTS: &str = "implements";

// The constructor Vim supplies for a class that declares none. Behind
// a dot the name is the language's, and a constructor a class does
// declare still takes the credit, because the mark is read only where
// nothing resolved.
// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
const NEW: &str = "new";

// Vim9's keyed container. A member access on one reads a key, which
// `recv_type` reports as this type because it reports the outermost
// one: `dict<string, Config>` is a dict. No class can carry the name,
// since Vim9 requires a capital, so the test cannot meet a project's
// own type of that name.
// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
const DICT: &str = "dict";

// The commands whose arguments are Vim's options. Their abbreviations
// need no entry: the generated table carries the prefix each one
// accepts, so `setl` reaches `setlocal` through `canonical`.
// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
const SET_FAMILY: &[&str] = &["set", "setlocal", "setglobal"];

// The commands whose arguments are code: an expression, a command to
// run, or a statement that the parser reads by its own rules. Every
// other command of Vim takes text that Vim keeps for itself from the
// command to its end: a file, a keyword, a group, a pattern, a
// register, an event. The list of code is closed and short, where a
// list of text would grow with each plugin. A word marked as text
// still credits a symbol of its spelling, so a command missing here
// costs a count and never a finding.
// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/108
const CODE_ARGS: &[&str] = &[
    // An expression.
    "echo",
    "echon",
    "echomsg",
    "echoerr",
    "echoconsole",
    "echowindow",
    "execute",
    "call",
    "eval",
    "if",
    "elseif",
    "while",
    "for",
    "return",
    "throw",
    "var",
    "const",
    "final",
    "let",
    "unlet",
    "lockvar",
    "unlockvar",
    // A command to run.
    "windo",
    "bufdo",
    "tabdo",
    "argdo",
    "cdo",
    "ldo",
    "cfdo",
    "lfdo",
    "folddoopen",
    "folddoclosed",
    "global",
    "vglobal",
    "vim9cmd",
    "legacy",
    // A statement with rules of its own.
    "autocmd",
    "command",
    "substitute",
    "def",
    "function",
    "class",
    "enum",
    "interface",
    "type",
    "import",
    "export",
];

// The command that runs its argument as keys. It is apart from the
// family above because it takes a bar as one of those keys, so
// nothing ends it before the line does.
// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
const NORMAL: &str = "normal";

// What the name of every mapping and unmapping command ends with:
// `nnoremap`, `xmap`, `iunmap`.
// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
const MAP: &str = "map";

// The arguments a mapping command takes before its left side, each
// written in angle brackets. `expr` is apart because it also says the
// right side is an expression and no keys.
// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
const MAP_ARGS: &[&str] = &[
    "buffer", "nowait", "silent", "special", "script", "expr", "unique",
];
const EXPR: &str = "expr";

// What a mapping command maps as a key where a space stands before
// it, and what indexes, calls or reaches into a variable where none
// does.
// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/52
const KEYS: &[&str] = &["(", "[", "."];

// What can stand against a mapping command with no space between:
// its bang, and the bracket that opens its first argument or key
// name, as in `nnoremap<buffer>`.
// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/52
const AGAINST: &[&str] = &["!", "<"];

// The key names that make the right side of a mapping run a command
// line, where the word behind the name is a command.
// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
const RUNS: &[&str] = &["ScriptCmd", "Cmd"];

// What says the right side of a mapping holds code and not keys
// alone: a key name that runs or names code, the colon that opens a
// command line, and the bracket of a call.
// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
const CODE: &[&str] = &["ScriptCmd", "Cmd", "SID", "Plug", ":", "("];

// What stands before a bar that ends no command, as a pattern writes
// its alternation.
// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
const ESCAPE: &str = "\\";

// What Vim writes between two commands on one line. The lexer keeps a
// line that opens with one in the statement before it, so a bar stands
// inside a statement rather than ending it.
// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
const BAR: &str = "|";

// What a lambda written as a block follows.
const ARROW: &str = "=>";

// What closes a bracket, which opens no command at the head of a line.
const CLOSERS: &[&str] = &[")", "]", "}"];

// The scopes of a legacy function: its arguments and its variables.
const LEGACY_LOCALS: &[&str] = &["a", "l"];

// The command that defines a legacy function.
const FUNCTION: &str = "function";

// The scope letter of a global function, as in `def g:Name()`.
const GLOBAL: &str = "g";

// The colon that opens a command line, which Vim9 script requires
// before a range.
const COLON: &str = ":";

// What a range holds besides a line number: the whole buffer, the
// current line, the last line, an offset in either direction, and the
// two separators of a pair of addresses.
const RANGE: &[&str] = &["%", ".", "$", "+", "-", ",", ";"];

// Vim's scope letters, which stand before a colon and name where a
// variable lives rather than naming anything the project declares.
// `a:` is legacy, for a function's arguments, and is here because the
// scan reads legacy files too.
// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
pub(super) const SCOPES: &[&str] = &["a", "b", "g", "l", "s", "t", "v", "w"];

// Vim's command modifiers, which are the only words a command may
// stand behind. Twenty-three are the list at `:help <mods>`, and
// `legacy` is the Vim9 prefix at `:help :legacy`, which that list
// predates. They are short and settled enough to hold by hand where
// the commands themselves are generated. `filter` is a command but
// not a modifier, which the help says outright.
// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
const MODS: &[&str] = &[
    "aboveleft",
    "belowright",
    "botright",
    "browse",
    "confirm",
    "hide",
    "horizontal",
    "keepalt",
    "keepjumps",
    "keepmarks",
    "keeppatterns",
    "leftabove",
    "legacy",
    "lockmarks",
    "noautocmd",
    "noswapfile",
    "rightbelow",
    "sandbox",
    "silent",
    "tab",
    "topleft",
    "unsilent",
    "verbose",
    "vertical",
];

// Vim9's own type names, marked where they stand as a type and not
// where one of them is called: `string(x)` is a call to the builtin
// of that name, and the builtins are a separate question. No class,
// enum or interface can carry one of these names, because each has to
// start with an uppercase letter, but a variable can, so what makes
// the mark safe is that it is read only where nothing resolved.
// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
const TYPES: &[&str] = &[
    "any", "blob", "bool", "channel", "dict", "float", "func", "job", "list", "number", "object",
    "string", "tuple", "void",
];

// The names Vim9 reserves for its empty values. No declaration can
// carry one, with a single exception: an enum value can, which is why
// these are marked as the language's own rather than dropped with the
// keywords. A word dropped there is a credit lost, and an enum value
// of that name would be reported though every use of it stands.
const NULLS: &[&str] = &[
    "null_blob",
    "null_channel",
    "null_class",
    "null_dict",
    "null_function",
    "null_job",
    "null_list",
    "null_object",
    "null_partial",
    "null_string",
    "null_tuple",
];

// The builtins that take a name as text rather than as code, so that
// the name inside the string is a call site like any other. These are
// harvested word by word; the two lists below have a reader of their
// own, and no word is named twice.
const BY_NAME: &[&str] = &["call", "function", "funcref", EVAL];

// The builtin whose argument is an expression rather than one name,
// so that an option or a literal in it is Vim's own word.
// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
const EVAL: &str = "eval";

// Whose argument is Vim's own syntax rather than a name, read part by
// part in `exists`. Every script opens with `exists('s:is_loaded')`,
// which reads the variable as surely as any expression does.
const EXISTS: &[&str] = &["exists", "exists_compiled"];

// Whose argument is a command line Vim runs, read in `evaluated`.
// `exe` reaches it through the generated table, and `execute()` is the
// function of the same name.
//
// `win_execute` is not here, although it runs a command line as well.
// It takes that line as its second argument, and the gate reads two
// tokens back, so not one `win_execute` string in the corpora is
// reached at all. Reading one would need the gate widened to the
// enclosing call, and the interpolations left alone after that: the
// strings there are expressions, so harvesting one adds a second copy
// of every name the lexer has already read as code.
// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
const EXECUTE: &[&str] = &["execute"];

/// FUNCTION: Record every reference a file makes: calls, member
/// accesses, funcrefs read as values, type annotations, and the names
/// that `call()`, `function()` and `execute()` take as text.
///
/// A name that no symbol in the project declares resolves to nothing
/// and costs nothing, so the scan records what might be a reference
/// and lets resolution decide. What it must never record is a name it
/// cannot see: a word inside an ordinary string, a comment, or a
/// heredoc body, which is what the statements it walks have already
/// removed.
pub fn references(file: &Path, stmts: &[Vec<Tok>], out: &mut dyn Sink) {
    let types = Types::of_file(stmts);
    let mut scope = Scope::default();
    let mut locals = Locals::default();

    // The variables of each body around the one being read, innermost
    // last, so that the `enddef` of a def inside a def returns to what
    // the body around it had declared.
    // REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
    let mut outer: Vec<Locals> = Vec::new();
    let mut blocks = Blocks::default();
    let consts = shared::consts(stmts);

    for stmt in stmts {
        let words: Vec<&str> = stmt
            .iter()
            .filter(|t| t.kind == TokKind::Ident)
            .map(|t| t.text.as_str())
            .collect();

        if close_container(&words, &mut scope) {
            if scope.depth() == 0 {
                outer.clear();
            }

            locals = outer.pop().unwrap_or_default();
            blocks.clear();
            continue;
        }

        // The body a statement sits in, read from the one stack both
        // passes keep, so that a nested `enddef` returns to the body
        // around it rather than to the file.
        let origin = scope
            .body()
            .cloned()
            .unwrap_or_else(|| SymbolId::script(file));
        let in_def = scope.depth() > 0;

        // The type an alias names is used where the alias is, as the
        // calls of a body are used where the body is.
        // REFERENCE: https://github.com/Galvarcus/GhostCode/issues/88
        let origin = match alias_at(stmt) {
            Some(at) if !in_def && scope.owner.is_none() => {
                SymbolId::of(file, None, &stmt[at].text)
            }
            _ => origin,
        };

        // A declaration inside the body gives its name a type that
        // the calls after it are resolved against, and a loop binds
        // its variables for the statements the loop holds.
        locals.declare(stmt);
        locals.bind_loop(stmt);

        // A declaration's own name is not a use of itself, so the
        // statement is read from after it: a def's parameter types and
        // defaults, and a var's initialiser, are still references.
        let mut skip: Vec<usize> = declared_name_at(stmt, &words).into_iter().collect();

        // An unpacking declares every name in its brackets, and none
        // of them is a use of itself either.
        // REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
        let unpacked = types::unpacked_at(stmt);
        if !unpacked.is_empty() {
            skip = unpacked;
        }

        // A value of an enum states no keyword, so nothing above
        // finds the name its line declares. Several values may share
        // one line, which is why this is a list.
        // REFERENCE: https://github.com/Galvarcus/GhostCode/issues/23
        if skip.is_empty() && !in_def && scope.container == Container::Enum {
            skip = enum_values_at(stmt);
        }

        // A lambda written as a block binds its parameters for every
        // statement of the block, and this is one of them where a
        // block is still open.
        // REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
        let mut bound = bound_names(stmt, &words);
        bound.extend(blocks.names());

        // A variable every file shares is read by its full spelling,
        // and the name behind its scope is no bare name of the
        // project. The read is marked as the language's, because a
        // variable the project never writes is another plugin's or
        // the user's, and no gap.
        // REFERENCE: https://github.com/Galvarcus/GhostCode/issues/55
        //
        // A name with a gap in it is kept until every variable is
        // known, and then read as each one its fixed parts fit.
        let used = shared::uses(stmt, &consts);
        let mut passed = skip.clone();
        passed.extend(&used.taken);

        for read in used.found.into_iter().filter(|u| !u.write) {
            let line = stmt[read.at].line;

            match read.spelling {
                shared::Spelling::Exact(name) => out.re(Reference {
                    name,
                    recv: None,
                    file: file.to_path_buf(),
                    line,
                    origin: Some(origin.clone()),
                    target: None,
                    owned: true,
                    member: false,
                }),
                shared::Spelling::Fit {
                    head,
                    tail,
                    whole,
                    needs,
                } => out.fit(Fit {
                    head,
                    tail,
                    whole,
                    needs: needs.map(str::to_string),
                    file: file.to_path_buf(),
                    line,
                    origin: Some(origin.clone()),
                }),
            }
        }

        let mut sink = Collect {
            file,
            origin: &origin,
            owner: scope.owner.as_deref(),
            locals: &locals,
            types: &types,
            in_def,
            own: skip.first().map(|&at| stmt[at].text.as_str()),
            bound,
            out,
        };

        sink.statement(stmt, &passed);
        blocks.read(stmt);

        let around = scope.body().cloned();

        if let Some(id) = opens_body(file, stmt, &words, &mut scope) {
            let signature = Locals::of_signature(stmt);

            // A def inside a def reads the variables of the body
            // around it, so those stay in view under its parameters.
            // REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
            let inner = match around.filter(|_| scope.depth() > 0) {
                Some(body) => locals.inside(&body, signature),
                None => signature,
            };

            if scope.depth() > 0 {
                outer.push(std::mem::replace(&mut locals, inner));
            } else {
                locals = inner;
            }

            scope.bodies.push(id);
            blocks.clear();
        }
    }
}

/// Writes the references of one statement, so that the walk itself
/// says nothing about where they are stored.
struct Collect<'a> {
    file: &'a Path,
    origin: &'a SymbolId,
    owner: Option<&'a str>,
    locals: &'a Locals,
    types: &'a Types,
    in_def: bool,
    own: Option<&'a str>,
    bound: Vec<&'a str>,
    out: &'a mut dyn Sink,
}

impl Collect<'_> {
    /// METHOD: Read one statement, from the token after its own name.
    fn statement(&mut self, stmt: &[Tok], skip: &[usize]) {
        let heads = heads(stmt);
        let owned = command_at(stmt).and_then(|at| autocmd::owned(stmt, at));

        for (i, tok) in stmt.iter().enumerate() {
            if skip.contains(&i) {
                continue;
            }

            match tok.kind {
                TokKind::Ident => self.ident(stmt, i, tok, &heads, owned.as_ref()),
                TokKind::Str => self.text(stmt, i, tok),
                _ => {}
            }
        }
    }

    /// METHOD: Record a name, with its receiver where a dot gives it
    /// one, as in `menu.Open()`, `this.Shut()`, or `Color.Red`.
    fn ident(
        &mut self,
        stmt: &[Tok],
        i: usize,
        tok: &Tok,
        heads: &[usize],
        owned: Option<&Range<usize>>,
    ) {
        if KEYWORDS.contains(&tok.text.as_str()) {
            return;
        }

        if sigil(stmt, i, tok.text.as_str()) {
            return;
        }

        if in_notation(stmt, i) || in_augroup(stmt, i) || owned.is_some_and(|own| own.contains(&i))
        {
            return;
        }

        // A `:command` line states Vim's attributes and then the name
        // it declares, and a user command is Vim's name thereafter.
        // REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
        if in_command_def(stmt, i) {
            return;
        }

        // A name against a colon is a parameter or a key, not a use:
        // `{callback: OnDone}` uses OnDone, not callback.
        if stmt.get(i + 1).is_some_and(|t| t.text == ":") && !is_type_position(stmt, i) {
            return;
        }

        // Vim's scope notation is three tokens, because the lexer
        // cannot let a name swallow a colon that an annotation writes
        // against it. The letter is Vim's own either way.
        // REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
        if scoped(stmt, i, tok.text.as_str()) {
            return;
        }

        let recv = types::recv_type(stmt, i, self.owner, self.locals, self.types);
        let word = tok.text.as_str();

        // A dict reads a key, and a key is no symbol of the project's:
        // `ctx.row`, where `ctx` is a `dict<any>`. Whatever the dict
        // holds was credited where it was put in, so a funcref stored
        // under a key keeps the credit of its own name and loses
        // nothing here. `any` is not this case: there the type is
        // unknown rather than keyed, and every candidate member must
        // still take the credit.
        // REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
        if recv.as_deref() == Some(DICT) {
            return;
        }

        // A variable of this body is placed already. It is dropped
        // rather than marked, because a mark is read only after
        // resolution, and by then a project symbol of the same name
        // has taken a credit the variable never gave it.
        if recv.is_none() && self.local(word) {
            return;
        }

        // A write is not a read. A variable the body declares and only
        // ever assigns to is exactly what the local class exists to
        // find, so an assignment must not credit it.
        //
        // Only inside a body. `Locals` records a script-level
        // declaration as well, and a script variable's write still
        // credits it: that is the write-only class, not this one.
        // REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
        if recv.is_none()
            && self.in_def
            && self.locals.bound_by(word) == Some(types::Bound::Declared)
            && written(stmt, i)
        {
            return;
        }

        // A call of a function that gives a whole scope is no
        // reference, and a read of what it gives holds only in a
        // project that names the function, so the name is recorded.
        // Any use of the name counts, called or not, because the
        // function can be passed as a value and called elsewhere.
        // REFERENCE: https://github.com/Galvarcus/GhostCode/issues/61
        if shared::gives_scope(word) {
            self.out.give(word);
        }

        // A called lowercase name is Vim's own, because Vim refuses a
        // `def` and a funcref variable whose name does not start with
        // a capital. It is dropped for the same reason a local is: a
        // script variable may carry the name, and resolution would
        // hand it a credit from every call of Vim's function.
        // REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
        if recv.is_none() && called(stmt, i) && builtins::has(word) {
            return;
        }

        // A word at the head of a statement is where Vim reads a
        // command, and a command is Vim's name rather than one the
        // project could declare. Anywhere else the same word is a
        // value: `echo` is itself a command, so the word after one
        // may well be the project's.
        // REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
        // Vim accepts any unambiguous prefix of a command, and 43 of
        // the lowercase names the corpora declare are themselves a
        // legal abbreviation, so an abbreviation is marked as the
        // language's rather than dropped: a project symbol of that
        // spelling still takes the credit, and where none exists the
        // name is not counted as unplaced.
        // REFERENCE: https://github.com/Galvarcus/GhostCode/issues/31
        //
        // A word with a capital there is a user command, which Vim
        // owns once a plugin defines it. Vim9 script reads nothing
        // else at the head of a statement unless the word is called,
        // reached into or assigned to, and `in_command` refuses those.
        let vims = recv.is_none()
            && in_command(stmt, i, heads)
            && (excmds::canonical(word).is_some() || user_command(word));

        if vims && excmds::has(word) {
            return;
        }

        let member = i > 0 && stmt[i - 1].text == DOT;

        let owned = vims
            || (member && word == NEW)
            || (recv.is_none() && set_args(stmt, i, heads))
            || text_args(stmt, i, heads)
            || (recv.is_none() && map_args(stmt, i))
            || NULLS.contains(&word)
            || (TYPES.contains(&word) && in_type(stmt, i) && !called(stmt, i))
            || legacy_local(stmt, i)
            || legacy_signature(stmt, i);

        self.out.re(Reference {
            name: tok.text.clone(),
            recv,
            file: self.file.to_path_buf(),
            line: tok.line,
            origin: Some(self.origin.clone()),
            // A variable of a body around this one is named outright,
            // because the id of this body does not lead to it.
            // REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
            target: self
                .locals
                .around(word)
                .filter(|_| !member)
                .map(|body| SymbolId::in_scope(body, word)),
            owned,
            member,
        });
    }

    /// METHOD: Whether a name is a variable of the code around it: a
    /// parameter, a declaration, a loop variable, or a parameter of a
    /// lambda. None of them is a symbol of the project, so none of
    /// them can be a reference to one.
    ///
    /// A name a parameter list binds is answered on any statement,
    /// because a parameter is never a symbol. A variable of a body is
    /// answered only inside one: at script level the same names are
    /// script variables, which are symbols, and the reads of them are
    /// the credits that keep them off the report. The name the
    /// statement itself declares is left alone as well, because
    /// `var Menu = Menu.new()` names the class on the right, and that
    /// is a credit the class is owed.
    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
    fn local(&self, word: &str) -> bool {
        if self.bound.contains(&word) {
            return true;
        }

        if Some(word) == self.own {
            return false;
        }

        // A loop at script level binds its variable as one in a body
        // does, and declares no symbol either. A declaration there is
        // a script variable, which is a symbol, so the loop variable
        // is the only binding answered outside a body.
        // REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
        if !self.in_def {
            return self.locals.bound_by(word) == Some(types::Bound::Loop);
        }

        // A `var` or `const` of this body is a symbol now, so its
        // read is a reference that resolves to it. A `final`, a
        // parameter and a loop variable are not symbols, so their
        // reads are still dropped: resolution has nothing to place
        // them on, and an emitted read would fall through to a
        // project symbol of the same name and credit it.
        // REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
        matches!(
            self.locals.bound_by(word),
            Some(types::Bound::Final | types::Bound::Parameter | types::Bound::Loop)
        )
    }

    /// METHOD: Record what a string holds. A builtin that takes a name
    /// as text names it outright, so those become references. Every
    /// other string is kept as text, to be matched against the
    /// project's own names once they are all known: Vim evaluates text
    /// in places no parser sees, and a name used only there is used.
    fn text(&mut self, stmt: &[Tok], i: usize, tok: &Tok) {
        // A function that gives a whole scope can be named as text
        // and called through a value, so its name in a string is a
        // use of it.
        // REFERENCE: https://github.com/Galvarcus/GhostCode/issues/66
        for name in shared::scope_givers(&tok.text) {
            self.out.give(name);
        }

        // The word before the string names what reads it, as a command
        // in `execute 'x'` or as a call in `exists('x')`, where a
        // bracket stands between.
        let gate = stmt[..i]
            .iter()
            .rev()
            .take(2)
            .enumerate()
            .find_map(|(back, t)| gate_of(&t.text, back == 0));

        let Some(gate) = gate else {
            self.out.text(Text {
                text: unquote(&tok.text),
                file: self.file.to_path_buf(),
                line: tok.line,
                origin: Some(self.origin.clone()),
            });
            return;
        };

        let arg = unquote(&tok.text);

        // `exists()` takes Vim's own syntax rather than a bare name: a
        // scope prefix, an option, a feature, an autocommand group.
        // The reader answers which of its words a project symbol could
        // carry, and only those are left unmarked.
        // REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
        let bare = |names: Vec<(String, bool)>| names.into_iter().map(Word::bare).collect();

        let names: Vec<Word> = if EXISTS.contains(&gate) {
            bare(exists::names(&arg))
        } else if EXECUTE.contains(&gate) {
            evaluated::names(&arg)
        } else if gate == EVAL {
            bare(evaluated::loose(&arg))
        } else {
            bare(identifiers(&arg).into_iter().map(|n| (n, false)).collect())
        };

        for Word { name, vims, recv } in names {
            // An interpolation is lexed as code as well, so its names
            // have been through `ident` already, and a variable of
            // the code around the string is dropped there. This is
            // the second reading of the same name, and it has to
            // agree. It goes by spelling, so a word of the text that
            // matches such a variable is dropped with it.
            // REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
            if EXECUTE.contains(&gate) && self.local(&name) {
                continue;
            }

            // A word with a receiver stands behind a dot, so it is a
            // member, as the scan of the code reads it.
            // REFERENCE: https://github.com/Galvarcus/GhostCode/issues/71
            let member = recv.is_some();

            self.out.re(Reference {
                name,
                recv,
                file: self.file.to_path_buf(),
                line: tok.line,
                origin: Some(self.origin.clone()),
                target: None,
                owned: vims,
                member,
            });
        }
    }
}

/// FUNCTION: The names a statement binds as parameters: those of a
/// signature, and those of every lambda the statement holds.
///
/// A signature declares its parameters exactly as a `var` declares
/// its name, and the walk already skips that one. The colon rule
/// cannot do it, because the colon of `amt: number` introduces a type
/// and so is not the colon of a dictionary key.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
fn bound_names<'a>(stmt: &'a [Tok], words: &[&str]) -> Vec<&'a str> {
    let mut names = types::lambda_params(stmt);

    let (_, rest) = strip_export(words);
    if strip_modifiers(rest).first().copied() == Some("def") {
        names.extend(types::param_names(stmt));
    }

    names
}

/// FUNCTION: The index of the name a statement declares, which is a
/// declaration rather than a use of itself.
fn declared_name_at(stmt: &[Tok], words: &[&str]) -> Option<usize> {
    if let Some(at) = alias_at(stmt) {
        return Some(at);
    }

    let (_, rest) = strip_export(words);
    let rest = strip_modifiers(rest);

    let keyword = rest.first().copied()?;
    if !matches!(
        keyword,
        "def" | "var" | "const" | "class" | "enum" | "interface" | "import"
    ) {
        return None;
    }

    let at = stmt.iter().position(|t| t.text == keyword)?;
    let name = stmt
        .iter()
        .enumerate()
        .skip(at + 1)
        .find(|(_, t)| t.kind == TokKind::Ident)
        .map(|(i, _)| i)?;

    Some(global_def_at(stmt, name).unwrap_or(name))
}

/// FUNCTION: The name a `def` statement declares.
///
/// `def g:Name()` declares a global function, and the word after
/// `def` is then the scope letter and not the name.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
fn def_name<'a>(stmt: &'a [Tok], rest: &[&'a str]) -> Option<&'a str> {
    let first = rest.get(1).copied()?;

    let behind = stmt
        .iter()
        .position(|t| t.text == first)
        .and_then(|at| global_def_at(stmt, at));

    Some(behind.map_or(first, |at| stmt[at].text.as_str()))
}

/// FUNCTION: Whether a `def` statement declares a global function,
/// `def g:Name`.
fn def_global(stmt: &[Tok], rest: &[&str]) -> bool {
    rest.get(1)
        .and_then(|first| stmt.iter().position(|t| t.text == *first))
        .and_then(|at| global_def_at(stmt, at))
        .is_some()
}

/// FUNCTION: Where the name behind the global scope stands, when the
/// word at `at` is that scope letter with a colon and a name glued
/// behind it.
fn global_def_at(stmt: &[Tok], at: usize) -> Option<usize> {
    let colon = stmt.get(at + 1)?;
    let name = stmt.get(at + 2)?;

    (stmt[at].text == GLOBAL
        && colon.text == COLON
        && colon.glued
        && name.glued
        && name.kind == TokKind::Ident)
        .then_some(at + 2)
}

/// FUNCTION: The symbol a statement opens a body for, so that what
/// follows belongs to it.
fn opens_body(file: &Path, stmt: &[Tok], words: &[&str], scope: &mut Scope) -> Option<SymbolId> {
    let (_, rest) = strip_export(words);
    let rest = strip_modifiers(rest);

    if let Some((container, name)) = container_name(rest) {
        scope.owner = Some(name.to_string());
        scope.container = container;
        scope.bodies.clear();
        return None;
    }

    body_id(file, stmt, words, scope)
}

/// FUNCTION: The id of the body a `def` statement opens, or none when
/// the statement is not a `def` or opens no body.
///
/// Both passes read this, so that neither can disagree with the other
/// about which body a statement belongs to.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
fn body_id(file: &Path, stmt: &[Tok], words: &[&str], scope: &Scope) -> Option<SymbolId> {
    let (_, rest) = strip_export(words);
    let rest = strip_modifiers(rest);

    if rest.first().copied() != Some("def") {
        return None;
    }

    let name = def_name(stmt, rest)?;
    if !stmt.iter().any(|t| t.text == "(") {
        return None;
    }

    // A signature with no body declares nothing to credit, so the
    // references after it keep the origin they had. Naming it would
    // key them on a symbol the declarations never recorded, and the
    // walk would drop every one of those edges.
    if !opens_def_body(words, scope) {
        return None;
    }

    Some(SymbolId::of(file, scope.owner.as_deref(), name))
}

/// FUNCTION: The class a class statement extends, if it extends one.
/// A class of another file stands behind the alias of its import, and
/// the name of the class is the part after the last dot.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/82
fn base_name<'a>(words: &'a [&'a str]) -> Option<&'a str> {
    let at = words.iter().position(|w| *w == EXTENDS)?;
    let base = words[at + 1..]
        .iter()
        .take_while(|w| **w != IMPLEMENTS)
        .last()?;

    base.rsplit(DOT).next()
}

/// FUNCTION: The container a statement opens and the name it gives
/// it, if it opens one.
fn container_name<'a>(words: &'a [&'a str]) -> Option<(Container, &'a str)> {
    let (keyword, rest) = words.split_first()?;

    let container = match *keyword {
        "class" => Container::Class,
        "enum" => Container::Enum,
        "interface" => Container::Interface,
        _ => return None,
    };

    Some((container, *rest.first()?))
}

/// FUNCTION: Whether a `def` statement opens a body that an `enddef`
/// will close.
///
/// A signature in an interface and an abstract method both declare a
/// method without writing one, so nothing follows them to skip and no
/// `enddef` ever arrives. A depth raised for either is never lowered,
/// and the rest of the container is read as that method's locals.
fn opens_def_body(words: &[&str], scope: &Scope) -> bool {
    if scope.container == Container::Interface {
        return false;
    }

    let (_, rest) = strip_export(words);

    !rest
        .iter()
        .take_while(|w| MODIFIERS.contains(w))
        .any(|w| *w == "abstract")
}

/// FUNCTION: Whether a type word is called rather than named as a
/// type. `func` is the one type word whose type carries a bracket of
/// its own, as `func(number): bool` does.
fn called(stmt: &[Tok], i: usize) -> bool {
    stmt[i].text != "func" && stmt.get(i + 1).is_some_and(|t| t.text == "(")
}

/// FUNCTION: Whether a word can name a user command, which Vim
/// requires to start with a capital.
pub(super) fn user_command(word: &str) -> bool {
    word.starts_with(|c: char| c.is_ascii_uppercase())
}

/// FUNCTION: Whether a word can name a type of the project: a class,
/// an enum, an interface or a type alias. Vim refuses each of the
/// four without a capital first, with E1314, E1415, E1343 and E1394.
///
/// The rule has the form of the one for a user command and is a
/// different fact of Vim, so it has a function of its own.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/70
fn type_name(word: &str) -> bool {
    word.starts_with(|c: char| c.is_ascii_uppercase())
}

/// FUNCTION: Whether a word is one of Vim's command modifiers,
/// written whole or abbreviated. `MODS` holds the 24 full names, and
/// the generated table carries the prefix each one accepts, so `sil`
/// needs no entry of its own.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/31
fn modifier(word: &str) -> bool {
    excmds::canonical(word).is_some_and(|name| MODS.contains(&name))
}

/// FUNCTION: The command a statement runs, past any modifier before
/// it, which is what tells the rules of one command from another.
fn head(stmt: &[Tok]) -> Option<&str> {
    command_at(stmt).map(|at| stmt[at].text.as_str())
}

/// FUNCTION: Whether a command's arguments carry Vim's angle-bracket
/// notation, which the mapping, menu and abbreviation commands do,
/// and so do an autocommand in its pattern and the body of a
/// `:command`, where `<q-args>` hands the arguments to the handler.
///
/// Vim has 84 of the first kind and builds every one from four stems,
/// so the stem is what this tests, against the generated table so
/// that a name of the project's cannot match. A command this misses
/// only leaves its notation counted, which is the safe direction: the
/// notation is never a name the project declares, so no credit rests
/// on recognising the command.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
fn notation(word: &str) -> bool {
    let Some(name) = excmds::canonical(word) else {
        return false;
    };

    matches!(name, "autocmd" | "doautocmd" | "doautoall" | "command")
        || name.ends_with("map")
        || name.ends_with("mapclear")
        || name.ends_with("menu")
        || name.ends_with("abbrev")
        || name.ends_with("abbreviate")
}

/// FUNCTION: Whether a statement is `:augroup`, which takes the name
/// of a group and nothing else.
///
/// A group lives in Vim's namespace rather than the project's, so no
/// word of such a line is a name the project declares. The other
/// autocommand forms are read part by part, in `autocmd`, which also
/// carries the `++once` and `++nested` flags this rule used to answer
/// by their plus signs alone.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
fn in_augroup(stmt: &[Tok], i: usize) -> bool {
    let Some(at) = command_at(stmt) else {
        return false;
    };

    if !reads_command(stmt, at) || !matches!(excmds::canonical(&stmt[at].text), Some("augroup")) {
        return false;
    }

    // A bar ends the command, so the line owns its own words alone:
    // the `Fn()` of `augroup foo | autocmd BufRead * Fn()` is the
    // project's.
    stmt[..i].iter().all(|tok| tok.text != BAR)
}

/// FUNCTION: Whether a name is one of Vim's key words, standing
/// inside the angle brackets of a mapping statement.
///
/// Nothing the project owns can be in there. `<SID>Func`,
/// `<Plug>(Name)` and `<ScriptCmd>Close()` each put the name after
/// the closing bracket, which is why what a mapping runs keeps its
/// reference while `<buffer>`, `<nowait>` and the parts of `<C-x>` do
/// not.
///
/// The rule is anchored to the statement rather than to the brackets
/// alone, because `list<string>` and `a < b` wear the same brackets
/// and neither is notation.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
fn in_notation(stmt: &[Tok], i: usize) -> bool {
    let reads = command_at(stmt).is_some_and(|at| reads_command(stmt, at));

    if !reads || !head(stmt).is_some_and(notation) {
        return false;
    }

    // The nearest bracket behind the name says whether it is inside a
    // span, and a span has to close for the brackets to be notation
    // rather than a comparison.
    let open = stmt[..i]
        .iter()
        .rev()
        .find(|t| t.text == "<" || t.text == ">")
        .is_some_and(|t| t.text == "<");

    open && stmt[i + 1..].iter().any(|t| t.text == ">")
}

/// FUNCTION: Whether a name is Vim's own because it opens with one of
/// Vim's sigils: `&` an option, `$` an environment variable, `@` a
/// register.
///
/// This needs no table of Vim's option names. A Vim9 declaration
/// cannot open with a sigil, so no symbol the project declares can
/// carry such a name, and the sigil alone settles it.
///
/// The scoped forms `&l:wrap` and `&g:wrap` lex as three tokens,
/// because the lexer ends a name at a colon so that an annotation can
/// write `x: Foo`. The option word after such a sigil is Vim's too.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
fn sigil(stmt: &[Tok], i: usize, word: &str) -> bool {
    if matches!(word.chars().next(), Some('&' | '$' | '@')) {
        return true;
    }

    i >= 2 && stmt[i - 1].text == ":" && stmt[i - 2].text.starts_with('&')
}

/// FUNCTION: Whether a name belongs to Vim's scope notation, as the
/// `v` and the `version` of `v:version` both do.
///
/// The scope letter is Vim's wherever it stands. The name after the
/// colon is Vim's only in `v:`, which is Vim's own namespace entirely;
/// `g:`, `b:`, `w:` and `t:` hold names the project or the user chose,
/// and those keep their references.
///
/// A dictionary excludes the second rule, because a key named like a
/// scope letter would otherwise hide the value beside it: `{v: Wide}`
/// uses `Wide`. A ternary excludes nothing, because the name before
/// its colon is not a scope letter unless the project named a
/// variable `v`, which it may, and which costs that variable one
/// credit of the many it has.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
fn scoped(stmt: &[Tok], i: usize, word: &str) -> bool {
    if SCOPES.contains(&word) && stmt.get(i + 1).is_some_and(|t| t.text == ":") {
        return true;
    }

    i >= 2 && stmt[i - 1].text == ":" && stmt[i - 2].text == "v" && is_type_position(stmt, i)
}

/// FUNCTION: Whether a name stands behind `a:` or `l:`, which hold
/// the arguments and the variables of a legacy function.
///
/// Neither can be a symbol of the project. The colon and the name
/// are glued, which is what tells the scope from a conditional whose
/// colon stands apart.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
fn legacy_local(stmt: &[Tok], i: usize) -> bool {
    i >= 2
        && stmt[i].glued
        && stmt[i - 1].glued
        && stmt[i - 1].text == COLON
        && LEGACY_LOCALS.contains(&stmt[i - 2].text.as_str())
}

/// FUNCTION: Whether a name is a parameter or a flag of a legacy
/// `:function` line: behind the bracket that opens its parameters.
///
/// The parameters are read through `a:`, and `abort`, `range`, `dict`
/// and `closure` are words of Vim. A call of the `function()` builtin
/// is no such line, which `reads_command` answers.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
fn legacy_signature(stmt: &[Tok], i: usize) -> bool {
    let Some(at) = command_at(stmt) else {
        return false;
    };

    if !reads_command(stmt, at) || excmds::canonical(&stmt[at].text) != Some(FUNCTION) {
        return false;
    }

    stmt[at..i].iter().any(|tok| tok.text == "(")
}

/// FUNCTION: Where a `:command` statement names the command, after
/// Vim's attributes and before the handler.
///
/// An attribute carries no delimiter the lexer keeps, so each is
/// consumed by its shape: `-bar`, or `-nargs=?`, or
/// `-complete=customlist,Func`, where the word after the comma names
/// a function of the project's. A shape this does not expect ends the
/// walk, which leaves the rest of the line counted rather than
/// dropping a name the project owns.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
fn command_name_at(stmt: &[Tok]) -> Option<usize> {
    let head_at = stmt
        .iter()
        .position(|t| t.text != "!" && !modifier(&t.text))?;

    let mut i = head_at + 1;
    while let Some(tok) = stmt.get(i) {
        if tok.text == "!" {
            i += 1;
            continue;
        }

        if tok.text != "-" {
            return Some(i);
        }

        i += 2;
        if stmt.get(i).is_some_and(|t| t.text == "=") {
            i += 2;

            if stmt.get(i).is_some_and(|t| t.text == ",") {
                i += 2;
            }
        }
    }

    None
}

/// FUNCTION: Whether a token of a `:command` or `:delcommand`
/// statement is Vim's own: an attribute, an attribute's value, or the
/// name the statement declares or removes.
///
/// A user command is a name Vim owns once the plugin defines it, so
/// no symbol of the project's is ever credited by one. What the line
/// does carry is the completion function after a comma and the
/// handler after the name, and both are left alone: the handler is
/// often the only caller the function has.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
fn in_command_def(stmt: &[Tok], i: usize) -> bool {
    if !matches!(
        head(stmt).and_then(excmds::canonical),
        Some("command" | "delcommand")
    ) {
        return false;
    }

    let Some(name_at) = command_name_at(stmt) else {
        return false;
    };

    if i == name_at {
        return true;
    }

    i > 0 && i < name_at && stmt[i - 1].text != ","
}

/// FUNCTION: Whether the name at a position is being written without
/// being read.
///
/// Only a name opening the statement, or one in a list that opens it,
/// because that is where Vim reads an assignment target.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
fn written(stmt: &[Tok], i: usize) -> bool {
    if i == 0 {
        return assigns(stmt, 1);
    }

    unpack_target(stmt, i)
}

/// FUNCTION: Whether the token at a position is an assignment that
/// writes and does not read.
fn assigns(stmt: &[Tok], at: usize) -> bool {
    stmt.get(at)
        .is_some_and(|t| WRITES.contains(&t.text.as_str()))
}

/// FUNCTION: Whether the name at a position is a whole part of a list
/// that opens the statement and that an assignment follows, as `a`
/// and `b` are in `[a, b] = F()`.
///
/// A part that is more than a name, such as `d.key` or `l[0]`, reads
/// the variable that holds the item, so only a name that stands alone
/// between the separators of the list is written.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/62
fn unpack_target(stmt: &[Tok], i: usize) -> bool {
    if stmt.first().map(|t| t.text.as_str()) != Some("[") {
        return false;
    }

    let Some(close) = types::closing(stmt, 0) else {
        return false;
    };

    if i >= close || !assigns(stmt, close + 1) {
        return false;
    }

    let inner = stmt[1..i]
        .iter()
        .fold(0i32, |depth, tok| match tok.text.as_str() {
            "(" | "[" | "{" => depth + 1,
            ")" | "]" | "}" => depth - 1,
            _ => depth,
        });

    inner == 0
        && matches!(stmt[i - 1].text.as_str(), "[" | "," | ";")
        && matches!(stmt[i + 1].text.as_str(), "," | ";" | "]")
}

/// FUNCTION: The name a word states for the reader of a string, with
/// an abbreviation resolved through the generated table, so that `exe`
/// reads as `execute`.
///
/// `against` says whether the word stands against the string, with no
/// token between. Only there is an abbreviation read, because `ev`,
/// `fu` and `cal` are names a project may give a variable: a message
/// held in one would otherwise be read as a call site, and a finding
/// that should never have been touched would disappear.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
fn gate_of(word: &str, against: bool) -> Option<&str> {
    if BY_NAME.contains(&word) || EXISTS.contains(&word) || EXECUTE.contains(&word) {
        return Some(word);
    }

    if !against {
        return None;
    }

    excmds::canonical(word).filter(|name| EXECUTE.contains(name))
}

/// FUNCTION: Whether the token at `i` is an argument of a set-family
/// command: at or after the nearest head whose command is one, and
/// before the bar that ends it.
///
/// An option name, an option's value, and a name the plugin invents
/// for Vim all stand there, and nothing the project declares can be
/// meant by one. The answer is a mark and never a drop, because an
/// option's value may name a project function in the autoload
/// convention: `set formatexpr=plugin#F()` is the only caller that
/// function has.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
pub(super) fn set_args(stmt: &[Tok], i: usize, heads: &[usize]) -> bool {
    let Some(at) = heads.iter().copied().filter(|head| *head < i).max() else {
        return false;
    };

    // `set` is a name Vim9 accepts for a variable, so the claim begins
    // only where Vim reads a command: `set['a'] = Fn()` assigns.
    if !reads_command(stmt, at) {
        return false;
    }

    if !excmds::canonical(&stmt[at].text).is_some_and(|name| SET_FAMILY.contains(&name)) {
        return false;
    }

    (at + 1..i).all(|k| !ends_command(stmt, k))
}

/// FUNCTION: Whether the token at a position is a bar that ends a
/// command. A bar behind a backslash is part of an argument.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/63
fn ends_command(stmt: &[Tok], k: usize) -> bool {
    stmt[k].text == BAR && (k == 0 || stmt[k - 1].text != ESCAPE)
}

/// FUNCTION: Whether the token at `i` is an argument of a command
/// whose arguments are Vim's own text: after a head whose command is
/// `:highlight`, `:syntax`, `:emenu` or `:normal`, and before the bar
/// that ends it.
///
/// A group, a menu and a key are names Vim keeps, and the project
/// declares nothing that one of these commands could mean. The answer
/// is a mark and never a drop, so a symbol that shares a spelling
/// with a group keeps the credit it had, and where none exists the
/// word is not counted. A receiver changes nothing, because the part
/// of a menu path behind a dot is the menu's as well.
///
/// An escaped bar ends nothing, because that is how a pattern writes
/// its alternation. `heads` still lists the word behind one, so the
/// nearest head cannot be trusted here and every head before the
/// token is asked. `:normal` takes every bar as a key.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
pub(super) fn text_args(stmt: &[Tok], i: usize, heads: &[usize]) -> bool {
    heads.iter().copied().filter(|at| *at < i).any(|at| {
        let Some(name) = excmds::canonical(&stmt[at].text) else {
            return false;
        };

        if !reads_command(stmt, at) {
            return false;
        }

        name == NORMAL || (text_family(name) && (at + 1..i).all(|k| !ends_command(stmt, k)))
    })
}

/// FUNCTION: Whether a command keeps its arguments as text of Vim's
/// own from the command to its end: every command but one whose
/// arguments are code, a modifier, and the commands whose arguments
/// have rules of their own.
fn text_family(name: &str) -> bool {
    !CODE_ARGS.contains(&name)
        && !MODS.contains(&name)
        && !SET_FAMILY.contains(&name)
        && !name.ends_with(MAP)
}

/// FUNCTION: Whether the last command of a statement takes the rest
/// of its line as text or as keys: a command of the text family,
/// `:normal`, or a mapping command.
///
/// The reader of a command line asks, because the words past a gap
/// in such a line are Vim's whatever the gap holds.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
pub(super) fn owns_line(stmt: &[Tok]) -> bool {
    heads(stmt)
        .into_iter()
        .filter(|at| stmt.get(*at).is_some_and(|t| !modifier(&t.text)))
        .max()
        .filter(|at| reads_command(stmt, *at))
        .and_then(|at| excmds::canonical(&stmt[at].text))
        .is_some_and(|name| name == NORMAL || text_family(name) || name.ends_with(MAP))
}

/// FUNCTION: Whether the token at `i` is a key of a mapping or an
/// unmapping command: a word of its left side, a word of a right side
/// that holds keys and no code, or a command of Vim's own that the
/// right side runs.
///
/// The left side is the first word behind the command that is not
/// one of its arguments, and a word is what stands between two
/// spaces. The right side is the project's wherever it may hold code:
/// under `<expr>` it is an expression, and with a key name that runs
/// code, a colon or a call it is a command line. There the one word
/// claimed is a command that stands against `<ScriptCmd>` or `<Cmd>`,
/// as `close` does, and a function there is called, which
/// `reads_command` refuses.
///
/// The answer is a mark, so a symbol of the same spelling keeps its
/// credit either way.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
pub(super) fn map_args(stmt: &[Tok], i: usize) -> bool {
    let Some(at) = command_at(stmt) else {
        return false;
    };

    if i <= at || !maps(stmt, at) || stmt[at..i].iter().any(|tok| tok.text == BAR) {
        return false;
    }

    // Each word behind the command, as the index it starts at.
    let starts: Vec<usize> = (at + 1..stmt.len()).filter(|k| !stmt[*k].glued).collect();
    let word = |n: usize| &stmt[starts[n]..starts.get(n + 1).copied().unwrap_or(stmt.len())];
    let Some(lhs) = (0..starts.len()).find(|n| map_arg(word(*n)).is_none()) else {
        return false;
    };

    let rhs = starts.get(lhs + 1).copied().unwrap_or(stmt.len());

    if i < rhs {
        return i >= starts[lhs];
    }

    if (0..lhs).any(|n| map_arg(word(n)) == Some(EXPR)) {
        return false;
    }

    if !stmt[rhs..]
        .iter()
        .any(|tok| CODE.contains(&tok.text.as_str()))
    {
        return true;
    }

    i >= 2
        && stmt[i - 1].text == ">"
        && RUNS.contains(&stmt[i - 2].text.as_str())
        && excmds::canonical(&stmt[i].text).is_some()
        && reads_command(stmt, i)
}

/// FUNCTION: Whether Vim reads a mapping or an unmapping command at
/// `at`.
///
/// The command stands apart from its arguments, with a space, a bang
/// or an angle bracket behind it: a word with a colon against it is
/// the key of a dictionary, and one with a comma is an item of a
/// list. A bracket or a dot behind that space is a key the command
/// maps. Against the word it indexes a variable or reaches into one,
/// and Vim9 allows no space there.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/52
fn maps(stmt: &[Tok], at: usize) -> bool {
    let Some(next) = stmt.get(at + 1) else {
        return false;
    };

    excmds::canonical(&stmt[at].text).is_some_and(|name| name.ends_with(MAP))
        && (!next.glued || AGAINST.contains(&next.text.as_str()))
        && (KEYS.contains(&next.text.as_str()) || reads_command(stmt, at))
}

/// FUNCTION: Where the first mapping or unmapping command of a line
/// stands, or none: at its head, behind a modifier, behind the pattern
/// of an autocommand, or behind a bar.
///
/// The lexer asks, because the keys behind such a command are no
/// code: a `#` there opens no comment and a bracket opens nothing.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/52
pub(super) fn map_at(line: &[Tok]) -> Option<usize> {
    heads(line)
        .into_iter()
        .find(|at| *at < line.len() && maps(line, *at))
}

/// FUNCTION: The argument of a mapping command that one word states,
/// as `<buffer>` states `buffer`, or none where the word is no such
/// argument.
fn map_arg(word: &[Tok]) -> Option<&str> {
    (word.len() == 3 && word[0].text == "<" && word[2].text == ">")
        .then(|| word[1].text.as_str())
        .filter(|name| MAP_ARGS.contains(name))
}

/// FUNCTION: Every index at which Vim reads a command: the statement's
/// own head, past any modifier, and the command an autocommand runs
/// after its pattern.
///
/// The list is built once for a statement and read for each of its
/// tokens, because a rule that walked the tokens before every name
/// would cost the square of the statement's length.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
pub(super) fn heads(stmt: &[Tok]) -> Vec<usize> {
    // A modifier stands where Vim reads a command as much as the
    // command behind it does, so the whole run of them is heads: the
    // `silent` of `silent echo x` is Vim's own word, not the project's.
    let first = command_at(stmt).unwrap_or(0);

    let mut at: Vec<usize> = (0..=first).collect();

    if let Some(body) = autocmd::body(stmt, first) {
        at.push(body);
    }

    // A bar ends one command and starts the next, which the lexer
    // keeps in the statement it opened: `if x | echo 1 | endif` is
    // three commands on one line.
    at.extend(
        (0..stmt.len())
            .filter(|i| ends_command(stmt, *i))
            .map(|i| i + 1)
            .filter(|next| *next < stmt.len()),
    );

    for line in block_lines(stmt) {
        let word = command_from(stmt, line).unwrap_or(line);

        at.extend(line..=word);
    }

    at
}

/// FUNCTION: Every index at which a line of a lambda block opens.
///
/// A lambda written as a block holds whole commands, and the lexer
/// keeps the block in the statement that opens it, so the head of
/// the statement is not the only place Vim reads a command there. A
/// line opens a command only where nothing but blocks is open: a line
/// inside a bracket, or inside a dictionary, continues an expression.
/// A brace opens a block where it follows the arrow and ends its
/// line, which is how Vim tells a block from a dictionary.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
fn block_lines(stmt: &[Tok]) -> Vec<usize> {
    let mut lines: Vec<usize> = Vec::new();

    // One entry for each bracket that is open, true for a block.
    let mut open: Vec<bool> = Vec::new();

    for (i, tok) in stmt.iter().enumerate() {
        let code = tok.kind != TokKind::Str;

        if code
            && open.last() == Some(&true)
            && i > 0
            && stmt[i - 1].line != tok.line
            && !CLOSERS.contains(&tok.text.as_str())
        {
            lines.push(i);
        }

        if !code {
            continue;
        }

        match tok.text.as_str() {
            "{" => {
                let block = i > 0
                    && stmt[i - 1].text == ARROW
                    && stmt.get(i + 1).is_some_and(|next| next.line != tok.line);

                open.push(block);
            }
            "(" | "[" => open.push(false),
            ")" | "]" | "}" => {
                open.pop();
            }
            _ => {}
        }
    }

    lines
}

/// FUNCTION: Whether a name stands where Vim reads a command: at the
/// head of the statement, after nothing but command modifiers.
///
/// What follows the name decides as well. A name that is assigned to,
/// indexed, reached into, or piped from is the project's own, however
/// much it looks like a command, because Vim reads none of those as a
/// command line. A name that is called is answered by the builtins
/// before this, and a project's own function cannot be here at all,
/// since Vim requires a capital.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
pub(super) fn in_command(stmt: &[Tok], i: usize, heads: &[usize]) -> bool {
    heads.contains(&i) && reads_command(stmt, i)
}

/// FUNCTION: Whether Vim reads a command at `at` rather than a value.
///
/// A name that is assigned to, indexed, reached into, piped from or
/// called is the project's own, however much it looks like a command:
/// `auto` abbreviates `autocmd` and `me` abbreviates `menu`, so
/// `auto = Helper()` would otherwise hand a whole line to Vim and take
/// the credit of every name on it. Every rule that claims the words
/// after a head asks this first.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
pub(super) fn reads_command(stmt: &[Tok], at: usize) -> bool {
    !stmt.get(at + 1).is_some_and(|t| {
        matches!(
            t.text.as_str(),
            "(" | "[" | "." | "->" | "=" | "+=" | "-=" | "*=" | "/=" | "%=" | "..=" | "<<=" | ">>="
        )
    })
}

/// FUNCTION: Where a statement's own command word stands, past any
/// modifier before it and past a colon with the range behind it.
///
/// Vim9 script reads a range only behind a colon, so `:%bwipe!` and
/// `:1,$delete` name a command where `%bwipe` alone would not.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
pub(super) fn command_at(stmt: &[Tok]) -> Option<usize> {
    command_from(stmt, 0)
}

/// FUNCTION: Where the command word of the command that opens at
/// `from` stands, past any modifier and past a colon with its range.
fn command_from(stmt: &[Tok], from: usize) -> Option<usize> {
    let at = from
        + stmt
            .get(from..)?
            .iter()
            .position(|t| t.text != "!" && !modifier(&t.text))?;

    if stmt[at].text != COLON {
        return Some(at);
    }

    stmt[at + 1..]
        .iter()
        .position(|t| !in_range(&t.text))
        .map(|past| at + 1 + past)
}

/// FUNCTION: Whether a token is part of a range: the whole buffer, a
/// line number, the current or the last line, an offset, or the
/// separator between two addresses.
fn in_range(text: &str) -> bool {
    RANGE.contains(&text) || text.bytes().all(|b| b.is_ascii_digit())
}

/// FUNCTION: Whether the token at a position stands as a type.
///
/// A type follows the colon of an annotation or of a return type, and
/// nests inside the brackets of another type, so the scan walks back
/// over what a type can hold and reads what comes before it. A value
/// after the colon of a dictionary entry or of a conditional answers
/// yes as well, and so does a name behind a scope prefix such as
/// `g:`, which a stream of tokens cannot tell from an annotation.
/// None of those costs a credit: the name is still resolved, and the
/// answer is read only where nothing resolved.
fn in_type(stmt: &[Tok], i: usize) -> bool {
    let mut at = i;

    while at > 0 {
        at -= 1;
        let text = stmt[at].text.as_str();

        if matches!(text, "<" | ">" | ">>" | "," | "(" | ")" | "?" | "...") || TYPES.contains(&text)
        {
            continue;
        }

        // A class stands in a list of types as a builtin type does,
        // alone or behind the alias of an import: `func(BI.Item,
        // list<BI.Item>)`. Only inside the brackets of a type, which
        // the token behind the walk says: a value before a comma in a
        // call would otherwise read as one.
        // REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
        if (text == DOT || type_name(text)) && class_in_types(stmt, at) {
            continue;
        }

        return text == ":" || (text == "=" && alias_at(stmt).is_some_and(|name| name + 1 == at));
    }

    false
}

/// FUNCTION: Where the name of a type alias stands, when a statement
/// declares one: `type`, a name, then `=`. The word alone is also the
/// function `type()`, which no `=` follows.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/88
fn alias_at(stmt: &[Tok]) -> Option<usize> {
    let start = usize::from(stmt.first()?.text == EXPORT);
    let keyword = stmt.get(start)?;
    let name = stmt.get(start + 1)?;

    (keyword.text == ALIAS
        && keyword.kind == TokKind::Ident
        && name.kind == TokKind::Ident
        && stmt.get(start + 2).is_some_and(|t| t.text == "="))
    .then_some(start + 1)
}

/// FUNCTION: Whether the class at `at` stands inside the brackets of
/// a type: the nearest bracket that is still open before it follows
/// a type word, as the `(` of `func(` and the `<` of `list<` do.
fn class_in_types(stmt: &[Tok], at: usize) -> bool {
    let mut closed = 0usize;

    for k in (0..at).rev() {
        match stmt[k].text.as_str() {
            ")" | ">" => closed += 1,
            ">>" => closed += 2,
            "(" | "<" if closed > 0 => closed -= 1,
            "(" | "<" => return k > 0 && TYPES.contains(&stmt[k - 1].text.as_str()),
            _ => {}
        }
    }

    false
}

/// FUNCTION: True when a colon after a name introduces a type rather
/// than separating a key from its value, as `var x: Config` does and
/// `{callback: OnDone}` does not.
fn is_type_position(stmt: &[Tok], i: usize) -> bool {
    let mut depth = 0i32;
    for tok in &stmt[..i] {
        match tok.text.as_str() {
            "{" => depth += 1,
            "}" => depth -= 1,
            _ => {}
        }
    }
    depth == 0
}

/// FUNCTION: Every identifier inside a piece of text.
pub fn identifiers(text: &str) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    let mut cur = String::new();

    for c in text.chars() {
        if c.is_ascii_alphanumeric() || c == '_' || c == '#' {
            cur.push(c);
        } else if !cur.is_empty() {
            out.push(std::mem::take(&mut cur));
        }
    }

    if !cur.is_empty() {
        out.push(cur);
    }

    out.retain(|name| name.starts_with(|c: char| c.is_ascii_alphabetic() || c == '_'));
    out
}
