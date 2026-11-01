//! The Vim9 parser: statements to declarations.
//!
//! License: GNU GPL 3.0

use std::path::Component;
use std::path::Path;
use std::path::PathBuf;

use crate::lang::vim9::lex::Tok;
use crate::lang::vim9::lex::TokKind;
use crate::model::Import;
use crate::model::Kind;
use crate::model::Sink;
use crate::model::Symbol;
use crate::model::SymbolId;

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
    in_def: bool,
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

    for stmt in stmts {
        let words: Vec<&str> = stmt
            .iter()
            .filter(|t| t.kind == TokKind::Ident)
            .map(|t| t.text.as_str())
            .collect();

        let Some(line) = stmt.first().map(|t| t.line) else {
            continue;
        };

        if close_container(&words, &mut scope) {
            continue;
        }

        if open_container(file, &words, line, &mut scope, out) {
            continue;
        }

        if function(file, stmt, &words, line, &scope, out) {
            scope.in_def = true;
            continue;
        }

        // Everything below is module level or class level. A
        // declaration inside a function body is a local.
        if scope.in_def {
            continue;
        }

        if scope.container == Container::Enum {
            enum_values(file, stmt, line, &scope, out);
            continue;
        }

        variable(file, &words, line, &scope, out);
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

    let Some((keyword, name)) = rest
        .split_first()
        .and_then(|(k, r)| r.first().map(|n| (*k, *n)))
    else {
        return false;
    };

    let container = match keyword {
        "class" => Container::Class,
        "enum" => Container::Enum,
        "interface" => Container::Interface,
        _ => return false,
    };

    let kind = match container {
        Container::Class => Kind::Class,
        Container::Enum => Kind::Enum,
        Container::Interface => Kind::Interface,
        Container::None => return false,
    };

    scope.owner = Some(name.to_string());
    scope.owner_exported = exported;
    scope.container = container;
    scope.in_def = false;

    out.sym(Symbol {
        id: SymbolId::of(file, None, name),
        kind,
        name: name.to_string(),
        file: file.to_path_buf(),
        line,
        exported,
        owner: None,
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
            scope.in_def = false;
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

    let Some(name) = rest.get(1) else {
        return false;
    };

    // A def's name is followed by its parameter list. Without one the
    // statement is not a declaration the analyzer can trust.
    if !stmt.iter().any(|t| t.text == "(") {
        return false;
    }

    if scope.container == Container::Interface {
        return true;
    }

    let (kind, exported) = member_kind(scope, Kind::Function, Kind::Method, name, exported);

    out.sym(Symbol {
        id: SymbolId::of(file, scope.owner.as_deref(), name),
        kind,
        name: (*name).to_string(),
        file: file.to_path_buf(),
        line,
        exported,
        owner: scope.owner.clone(),
    });

    true
}

/// FUNCTION: Record a `var`, `const`, or `final`: a script variable at
/// module level, or a field inside a class.
fn variable(file: &Path, words: &[&str], line: u32, scope: &Scope, out: &mut dyn Sink) {
    let (exported, rest) = strip_export(words);
    let rest = strip_modifiers(rest);

    if !matches!(rest.first().copied(), Some("var" | "const")) {
        return;
    }

    let Some(name) = rest.get(1) else {
        return;
    };

    let (kind, exported) = member_kind(scope, Kind::Variable, Kind::Field, name, exported);

    out.sym(Symbol {
        id: SymbolId::of(file, scope.owner.as_deref(), name),
        kind,
        name: (*name).to_string(),
        file: file.to_path_buf(),
        line,
        exported,
        owner: scope.owner.clone(),
    });
}

/// FUNCTION: Record the values an enum lists, which arrive several to
/// a line, with or without arguments: `Red, Green` and `Blue('b')`.
fn enum_values(file: &Path, stmt: &[Tok], line: u32, scope: &Scope, out: &mut dyn Sink) {
    let mut depth = 0i32;
    let mut want = true;

    for tok in stmt {
        match tok.text.as_str() {
            "(" | "[" | "{" => depth += 1,
            ")" | "]" | "}" => depth -= 1,
            "," if depth == 0 => want = true,
            _ => {
                if want && depth == 0 && tok.kind == TokKind::Ident {
                    out.sym(Symbol {
                        id: SymbolId::of(file, scope.owner.as_deref(), &tok.text),
                        kind: Kind::EnumValue,
                        name: tok.text.clone(),
                        file: file.to_path_buf(),
                        line,
                        exported: false,
                        owner: scope.owner.clone(),
                    });
                }
                want = false;
            }
        }
    }
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
