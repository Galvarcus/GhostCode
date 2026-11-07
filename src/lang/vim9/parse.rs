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
use crate::lang::vim9::excmds;
use crate::lang::vim9::exists;
use crate::lang::vim9::lex::Tok;
use crate::lang::vim9::lex::TokKind;
use crate::lang::vim9::types;
use crate::lang::vim9::types::Locals;
use crate::lang::vim9::types::Types;
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
            if let Some(id) = body_id(file, stmt, &words, &scope) {
                scope.bodies.push(id);
            }

            continue;
        }

        // A declaration inside a function body is a local, which is
        // a symbol of that body and of nothing wider.
        // REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
        if scope.depth() > 0 {
            local(file, &words, line, &scope, out);
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

    let Some((container, name)) = container_name(rest) else {
        return false;
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
        scope: None,
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
        scope: None,
    });
}

/// FUNCTION: Record a `var` or `const` inside a function body, scoped
/// to that body.
///
/// The declaring words are those `variable` accepts at module level,
/// so the same statement is not read differently one scope out. The
/// discard placeholder declares nothing worth recording.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
fn local(file: &Path, words: &[&str], line: u32, scope: &Scope, out: &mut dyn Sink) {
    let Some(body) = scope.body() else {
        return;
    };

    let (_, rest) = strip_export(words);
    let rest = strip_modifiers(rest);

    if !matches!(rest.first().copied(), Some("var" | "const")) {
        return;
    }

    let Some(name) = rest.get(1) else {
        return;
    };

    if *name == DISCARD {
        return;
    }

    // A name the language owns is dropped wherever it stands, so no
    // read of this variable ever reaches the reference list and the
    // analyzer cannot know whether it is used. Recording it would
    // make a finding of `var set = {}` read on the next line.
    // REFERENCE: https://github.com/Galvarcus/GhostCode/issues/31
    if KEYWORDS.contains(name) {
        return;
    }

    out.sym(Symbol {
        id: SymbolId::in_scope(body, name),
        kind: Kind::Variable,
        name: (*name).to_string(),
        file: file.to_path_buf(),
        line,
        exported: false,
        owner: scope.owner.clone(),
        scope: Some(body.clone()),
    });
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
const KEYWORDS: &[&str] = &[
    "vim9script",
    "def",
    "enddef",
    "class",
    "endclass",
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

// What Vim writes between two commands on one line. The lexer keeps a
// line that opens with one in the statement before it, so a bar stands
// inside a statement rather than ending it.
// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
const BAR: &str = "|";

// Vim's scope letters, which stand before a colon and name where a
// variable lives rather than naming anything the project declares.
// `a:` is legacy, for a function's arguments, and is here because the
// scan reads legacy files too.
// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
const SCOPES: &[&str] = &["a", "b", "g", "l", "s", "t", "v", "w"];

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
// the name inside the string is a call site like any other.
// The two of `BY_NAME` whose argument is Vim's own syntax rather than
// a name, read part by part in `exists`.
const EXISTS: &[&str] = &["exists", "exists_compiled"];

// The one whose argument is a command line Vim runs, read in
// `evaluated`. `exe` reaches it through the generated table, and
// `execute()` is the function of the same name.
//
// `win_execute` is not here. Its strings in the corpora are
// interpolated expressions, so harvesting them adds a second copy of
// names the lexer already reads as code, and 26 occurrences that name
// nothing. Reading such a string would have to leave its
// interpolations alone first.
// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
const EXECUTE: &[&str] = &["execute"];

const BY_NAME: &[&str] = &[
    "call",
    "function",
    "funcref",
    "execute",
    "eval",
    // Every script opens with `exists('s:is_loaded')`, which reads the
    // variable as surely as any expression does.
    "exists",
    "exists_compiled",
];

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

    for stmt in stmts {
        let words: Vec<&str> = stmt
            .iter()
            .filter(|t| t.kind == TokKind::Ident)
            .map(|t| t.text.as_str())
            .collect();

        if close_container(&words, &mut scope) {
            locals = Locals::default();
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

        // A declaration inside the body gives its name a type that
        // the calls after it are resolved against, and a loop binds
        // its variables for the statements the loop holds.
        locals.declare(stmt);
        locals.bind_loop(stmt);

        // A declaration's own name is not a use of itself, so the
        // statement is read from after it: a def's parameter types and
        // defaults, and a var's initialiser, are still references.
        let mut skip: Vec<usize> = declared_name_at(stmt, &words).into_iter().collect();

        // A value of an enum states no keyword, so nothing above
        // finds the name its line declares. Several values may share
        // one line, which is why this is a list.
        // REFERENCE: https://github.com/Galvarcus/GhostCode/issues/23
        if skip.is_empty() && !in_def && scope.container == Container::Enum {
            skip = enum_values_at(stmt);
        }

        let mut sink = Collect {
            file,
            origin: &origin,
            owner: scope.owner.as_deref(),
            locals: &locals,
            types: &types,
            in_def,
            own: skip.first().map(|&at| stmt[at].text.as_str()),
            bound: bound_names(stmt, &words),
            out,
        };

        sink.statement(stmt, &skip);

        if let Some(id) = opens_body(file, stmt, &words, &mut scope) {
            scope.bodies.push(id);
            locals = Locals::of_signature(stmt);
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
        let vims =
            recv.is_none() && in_command(stmt, i, heads) && excmds::canonical(word).is_some();

        if vims && excmds::has(word) {
            return;
        }

        let owned = vims
            || (recv.is_none() && set_args(stmt, i, heads))
            || NULLS.contains(&word)
            || (TYPES.contains(&word) && in_type(stmt, i) && !called(stmt, i));

        self.out.re(Reference {
            name: tok.text.clone(),
            recv,
            file: self.file.to_path_buf(),
            line: tok.line,
            origin: Some(self.origin.clone()),
            target: None,
            owned,
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

        if !self.in_def || Some(word) == self.own {
            return false;
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
        // The word before the string names what reads it, either as a
        // command, `execute 'x'`, or as the call whose arguments the
        // string sits in, `win_execute(id, 'x')`.
        let gate = stmt[..i]
            .iter()
            .rev()
            .take(2)
            .find_map(|t| gate_of(&t.text));

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
        let names: Vec<(String, bool)> = if EXISTS.contains(&gate) {
            exists::names(&arg)
        } else if EXECUTE.contains(&gate) {
            evaluated::names(&arg)
        } else {
            identifiers(&arg).into_iter().map(|n| (n, false)).collect()
        };

        for (name, owned) in names {
            self.out.re(Reference {
                name,
                recv: None,
                file: self.file.to_path_buf(),
                line: tok.line,
                origin: Some(self.origin.clone()),
                target: None,
                owned,
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

    let name = rest.get(1)?;
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
/// Only a name opening the statement, because that is where Vim reads
/// an assignment target. A destructuring assignment is not caught,
/// which leaves its write crediting the variable: that misses a
/// finding rather than inventing one.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
fn written(stmt: &[Tok], i: usize) -> bool {
    i == 0
        && stmt
            .get(1)
            .is_some_and(|t| WRITES.contains(&t.text.as_str()))
}

/// FUNCTION: The name a word states for the reader of a string, with
/// an abbreviation resolved through the generated table, so that `exe`
/// reads as `execute`.
fn gate_of(word: &str) -> Option<&str> {
    if BY_NAME.contains(&word) {
        return Some(word);
    }

    excmds::canonical(word).filter(|name| BY_NAME.contains(name))
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

    if !excmds::canonical(&stmt[at].text).is_some_and(|name| SET_FAMILY.contains(&name)) {
        return false;
    }

    stmt[at..i].iter().all(|tok| tok.text != BAR)
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
        stmt.iter()
            .enumerate()
            .filter(|(_, tok)| tok.text == BAR)
            .map(|(i, _)| i + 1)
            .filter(|next| *next < stmt.len()),
    );

    at
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
/// modifier before it.
pub(super) fn command_at(stmt: &[Tok]) -> Option<usize> {
    stmt.iter()
        .position(|t| t.text != "!" && !modifier(&t.text))
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

        return text == ":";
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
