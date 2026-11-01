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
use crate::model::Reference;
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

// The builtins that take a name as text rather than as code, so that
// the name inside the string is a call site like any other.
const BY_NAME: &[&str] = &["call", "function", "funcref", "execute", "eval"];

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
    let mut scope = Scope::default();
    let mut origin = SymbolId::script(file);

    for stmt in stmts {
        let words: Vec<&str> = stmt
            .iter()
            .filter(|t| t.kind == TokKind::Ident)
            .map(|t| t.text.as_str())
            .collect();

        if close_container(&words, &mut scope) {
            origin = SymbolId::script(file);
            continue;
        }

        let mut sink = Collect {
            file,
            origin: &origin,
            out,
        };

        // A declaration's own name is not a use of itself, so the
        // statement is read from after it: a def's parameter types and
        // defaults, and a var's initialiser, are still references.
        let skip = declared_name_at(stmt, &words);
        sink.statement(stmt, skip);

        if let Some(id) = opens_body(file, stmt, &words, &mut scope) {
            origin = id;
        }
    }
}

/// Writes the references of one statement, so that the walk itself
/// says nothing about where they are stored.
struct Collect<'a> {
    file: &'a Path,
    origin: &'a SymbolId,
    out: &'a mut dyn Sink,
}

impl Collect<'_> {
    /// METHOD: Read one statement, from the token after its own name.
    fn statement(&mut self, stmt: &[Tok], skip: Option<usize>) {
        for (i, tok) in stmt.iter().enumerate() {
            if Some(i) == skip {
                continue;
            }

            match tok.kind {
                TokKind::Ident => self.ident(stmt, i, tok),
                TokKind::Str => self.text(stmt, i, tok),
                _ => {}
            }
        }
    }

    /// METHOD: Record a name, with its receiver where a dot gives it
    /// one, as in `menu.Open()`, `this.Shut()`, or `Color.Red`.
    fn ident(&mut self, stmt: &[Tok], i: usize, tok: &Tok) {
        // A name against a colon is a parameter or a key, not a use:
        // `{callback: OnDone}` uses OnDone, not callback.
        if stmt.get(i + 1).is_some_and(|t| t.text == ":") && !is_type_position(stmt, i) {
            return;
        }

        let recv = match (stmt.get(i.wrapping_sub(1)), i) {
            (Some(dot), 1..) if dot.text == "." => stmt
                .get(i - 2)
                .filter(|t| t.kind == TokKind::Ident)
                .map(|t| t.text.clone()),
            _ => None,
        };

        self.out.re(Reference {
            name: tok.text.clone(),
            recv,
            file: self.file.to_path_buf(),
            line: tok.line,
            origin: Some(self.origin.clone()),
            target: None,
        });
    }

    /// METHOD: Record the names inside a string that a builtin takes
    /// as text, and nothing from any other string.
    fn text(&mut self, stmt: &[Tok], i: usize, tok: &Tok) {
        let by_name = stmt[..i]
            .iter()
            .rev()
            .take(2)
            .any(|t| BY_NAME.contains(&t.text.as_str()));

        if !by_name {
            return;
        }

        for name in identifiers(&unquote(&tok.text)) {
            self.out.re(Reference {
                name,
                recv: None,
                file: self.file.to_path_buf(),
                line: tok.line,
                origin: Some(self.origin.clone()),
                target: None,
            });
        }
    }
}

/// FUNCTION: The index of the name a statement declares, which is a
/// declaration rather than a use of itself.
fn declared_name_at(stmt: &[Tok], words: &[&str]) -> Option<usize> {
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
    stmt.iter()
        .enumerate()
        .skip(at + 1)
        .find(|(_, t)| t.kind == TokKind::Ident)
        .map(|(i, _)| i)
}

/// FUNCTION: The symbol a statement opens a body for, so that what
/// follows belongs to it.
fn opens_body(file: &Path, stmt: &[Tok], words: &[&str], scope: &mut Scope) -> Option<SymbolId> {
    let (_, rest) = strip_export(words);
    let rest = strip_modifiers(rest);

    if let Some(name) = container_name(rest) {
        scope.owner = Some(name.to_string());
        return None;
    }

    if rest.first().copied() != Some("def") {
        return None;
    }

    let name = rest.get(1)?;
    if !stmt.iter().any(|t| t.text == "(") {
        return None;
    }

    Some(SymbolId::of(file, scope.owner.as_deref(), name))
}

/// FUNCTION: The name of the class, enum or interface a statement
/// opens, if it opens one.
fn container_name<'a>(words: &'a [&'a str]) -> Option<&'a str> {
    match words.split_first() {
        Some((&("class" | "enum" | "interface"), rest)) => rest.first().copied(),
        _ => None,
    }
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

/// FUNCTION: Every identifier inside a piece of text, for the builtins
/// that take a name as a string.
fn identifiers(text: &str) -> Vec<String> {
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
