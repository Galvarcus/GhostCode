//! Vim9 type tracking: the type of a receiver, where one can be told.
//!
//! A dotted call's receiver is usually a plain variable, and without
//! its type `popup.Open()` could mean any `Open` in the project. The
//! declaration that gives it a type is in scope at the call, so the
//! scan reads it there, where a later stage no longer could.
//!
//! License: GNU GPL 3.0

use std::collections::HashMap;

use crate::lang::vim9::lex::Tok;
use crate::lang::vim9::lex::TokKind;

/// The types a file states: its class fields, by class, and its
/// module-level variables.
#[derive(Debug, Clone, Default)]
pub struct Types {
    fields: HashMap<String, HashMap<String, String>>,
    globals: HashMap<String, String>,
}

impl Types {
    /// METHOD: Read every declared type a file states, before any
    /// reference is resolved against them, because a field may be
    /// declared after the method that uses it.
    pub fn of_file(stmts: &[Vec<Tok>]) -> Self {
        let mut types = Self::default();
        let mut owner: Option<String> = None;
        let mut interface = false;
        let mut depth = 0u32;

        for stmt in stmts {
            let words: Vec<&str> = idents(stmt);

            match words.first().copied() {
                Some("endclass" | "endenum" | "endinterface") => {
                    owner = None;
                    interface = false;
                    depth = 0;
                    continue;
                }
                Some("enddef") => {
                    depth = depth.saturating_sub(1);
                    continue;
                }
                _ => {}
            }

            if let Some((keyword, name)) = opens_container(&words) {
                owner = Some(name.to_string());
                interface = keyword == "interface";
                depth = 0;
                continue;
            }

            if is_def(stmt, &words) {
                if !interface {
                    depth += 1;
                }

                continue;
            }

            if depth > 0 {
                continue;
            }

            if let Some((name, ty)) = declared_name(stmt) {
                match &owner {
                    Some(class) => {
                        types
                            .fields
                            .entry(class.clone())
                            .or_default()
                            .insert(name, ty);
                    }
                    None => {
                        types.globals.insert(name, ty);
                    }
                }
            }
        }

        types
    }

    /// METHOD: The type of a field of a class, where the class states
    /// one.
    pub fn field(&self, class: &str, field: &str) -> Option<&str> {
        self.fields.get(class)?.get(field).map(String::as_str)
    }

    /// METHOD: The type of a module-level variable, which is empty
    /// where the file declares the variable without one.
    pub fn global(&self, name: &str) -> Option<&str> {
        self.globals.get(name).map(String::as_str)
    }
}

/// What bound a name inside a function body. Only a `var` or a
/// `const` makes a symbol, so the rest keep being dropped from the
/// references; the distinction is what lets one be kept without
/// keeping all of them.
///
/// `Final` is apart from `Declared` because `strip_modifiers` eats
/// the word before the symbol emitter can see it, so a `final` can
/// never have a symbol for its read to resolve to. Keeping the read
/// dropped is what stops it crediting a project symbol of the name.
///
/// A lambda's parameter is absent on purpose: `bound_names` carries it
/// and the reference walk checks that first.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Bound {
    Declared,
    Final,
    Parameter,
    Loop,
}

/// The types in scope inside one function body: its parameters and the
/// variables it declares. A body's locals say nothing about any other
/// body, so this is rebuilt at each `def`.
#[derive(Debug, Clone, Default)]
pub struct Locals {
    vars: HashMap<String, (Bound, String)>,
}

impl Locals {
    /// METHOD: Read the parameter types a def's signature states.
    pub fn of_signature(stmt: &[Tok]) -> Self {
        let mut locals = Self::default();

        let Some(open) = stmt.iter().position(|t| t.text == "(") else {
            return locals;
        };
        let close = closing(stmt, open).unwrap_or(stmt.len());

        // A parameter with no type is still a variable, and knowing
        // that is what tells it from a class name used directly.
        for param in params(&stmt[open + 1..close]) {
            if let Some((name, ty)) = annotated(param) {
                locals.vars.insert(name, (Bound::Parameter, ty));
            } else if let Some(name) = param.first().filter(|t| t.kind == TokKind::Ident) {
                locals
                    .vars
                    .entry(name.text.clone())
                    .or_insert((Bound::Parameter, String::new()));
            }
        }

        locals
    }

    /// METHOD: Record the type of a variable a statement declares,
    /// whether it states one or builds one with a constructor.
    pub fn declare(&mut self, stmt: &[Tok]) {
        let bound = match declaring_word(stmt) {
            Some("final") => Bound::Final,
            _ => Bound::Declared,
        };

        // A declaration that unpacks a list declares every name in
        // its brackets, each with the type it states for itself.
        // REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
        for at in unpacked_at(stmt) {
            let ty = annotated(&stmt[at..]).map(|(_, ty)| ty).unwrap_or_default();
            self.vars.insert(stmt[at].text.clone(), (bound, ty));
        }

        if let Some((name, ty)) = declared_name(stmt) {
            self.vars.insert(name, (bound, ty));
        }
    }

    /// METHOD: Record the variables a `for` statement binds, as
    /// `for f in xs` binds one and `for [k, v] in items(d)` binds two.
    ///
    /// The loop states no type, so the type is empty: what matters is
    /// that the name is a variable of this body at all, which is what
    /// keeps it out of the reference list and stops a receiver of that
    /// name being read as a class naming itself.
    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
    pub fn bind_loop(&mut self, stmt: &[Tok]) {
        if stmt.first().map(|t| t.text.as_str()) != Some("for") {
            return;
        }

        let end = stmt
            .iter()
            .position(|t| t.text == "in")
            .unwrap_or(stmt.len());

        for tok in &stmt[1..end.max(1)] {
            if tok.kind == TokKind::Ident {
                self.vars
                    .entry(tok.text.clone())
                    .or_insert((Bound::Loop, String::new()));
            }
        }
    }

    /// METHOD: The type of a name in this body, where it has one.
    pub fn get(&self, name: &str) -> Option<&str> {
        self.vars.get(name).map(|(_, ty)| ty.as_str())
    }

    /// METHOD: What bound a name in this body, where it binds one.
    pub fn bound_by(&self, name: &str) -> Option<Bound> {
        self.vars.get(name).map(|(bound, _)| *bound)
    }

    /// METHOD: True when this body declares the name at all, which is
    /// what tells an untyped variable from a class name.
    pub fn holds(&self, name: &str) -> bool {
        self.vars.contains_key(name)
    }
}

/// FUNCTION: The parameters of a list, cut at the commas that
/// separate them and at no others.
///
/// A comma inside a parameter separates nothing: `func(string, Config)`
/// is one parameter's type and `[One, Two]` is one parameter's
/// default. Reading either comma as a separator takes the name after
/// it for a parameter, and a parameter is dropped from the references,
/// so the project symbol of that name loses a credit it is owed.
///
/// An angle bracket counts, because `tuple<number, Config>` holds a
/// comma as well. A comparison in a default leaves the depth wrong,
/// and the parameters after it are then not found, which costs the
/// count a name it could have placed and no symbol a credit.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
fn params(toks: &[Tok]) -> Vec<&[Tok]> {
    let mut out = Vec::new();
    let mut depth = 0i32;
    let mut start = 0;

    for (i, tok) in toks.iter().enumerate() {
        match tok.text.as_str() {
            "(" | "[" | "{" | "<" => depth += 1,
            ")" | "]" | "}" | ">" => depth -= 1,
            ">>" => depth -= 2,
            "," if depth == 0 => {
                out.push(&toks[start..i]);
                start = i + 1;
            }
            _ => {}
        }
    }

    out.push(&toks[start..]);
    out
}

/// FUNCTION: The names a parameter list binds, as a signature and a
/// lambda both write one: `(a, b: string, c = 1)`.
///
/// The first name of each parameter is its own, whether a type, a
/// default, or the `...` of a variadic follows it.
fn list_names(toks: &[Tok]) -> Vec<&str> {
    params(toks)
        .into_iter()
        .filter_map(|param| param.iter().find(|t| t.kind == TokKind::Ident))
        .map(|t| t.text.as_str())
        .collect()
}

/// FUNCTION: The names the parameter list of a signature binds, which
/// the signature declares rather than uses.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
pub fn param_names(stmt: &[Tok]) -> Vec<&str> {
    let Some(open) = stmt.iter().position(|t| t.text == "(") else {
        return Vec::new();
    };
    let close = closing(stmt, open).unwrap_or(stmt.len());

    list_names(&stmt[open + 1..close])
}

/// FUNCTION: The parameters of every lambda in one statement, which
/// are names of the lambda and of nothing else.
///
/// A lambda's parameters cannot join the body's variables, because the
/// statement that holds the lambda is where they end: a body that
/// writes `(_, Fmt) => Fmt` on one line may call its own `Fmt()` on
/// the next. Vim9 writes `=>` for nothing else, so the arrow is what
/// finds them.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
pub fn lambda_params(stmt: &[Tok]) -> Vec<&str> {
    let mut names = Vec::new();

    for at in 1..stmt.len() {
        if stmt[at].text == "=>" {
            names.extend(params_before(stmt, at));
        }
    }

    names
}

/// FUNCTION: The parameters of the one lambda whose arrow stands at a
/// position, or none where no parameter list stands before it.
fn params_before(stmt: &[Tok], arrow: usize) -> Vec<&str> {
    let Some(close) = list_end(stmt, arrow) else {
        return Vec::new();
    };
    let Some(open) = opening(stmt, close) else {
        return Vec::new();
    };

    list_names(&stmt[open + 1..close])
}

/// FUNCTION: The index of the bracket that closes the parameter list
/// of a lambda, given its arrow.
///
/// The bracket stands against the arrow, or a return type stands
/// between them: `(m: list<string>): string => m[1]`. The walk back
/// crosses only what a type is written with, so that anything else
/// before the arrow finds no list rather than a wrong one, and a wrong
/// one would drop a name the project is owed a credit for.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
fn list_end(stmt: &[Tok], arrow: usize) -> Option<usize> {
    let mut depth = 0i32;

    for i in (0..arrow).rev() {
        let tok = &stmt[i];

        match tok.text.as_str() {
            ")" if i + 1 == arrow => return Some(i),
            ">" => depth += 1,
            ">>" => depth += 2,
            "<" => depth -= 1,
            "," if depth > 0 => {}
            ":" if depth == 0 => {
                return (i > 0 && stmt[i - 1].text == ")").then_some(i - 1);
            }
            _ if tok.kind == TokKind::Ident => {}
            _ => return None,
        }
    }

    None
}

/// The lambdas written as a block that a statement stands inside, each
/// with the parameters it binds.
///
/// `lambda_params` ends a lambda with its statement, which holds for
/// one written as an expression. A block does not end there: a
/// declaring word inside it starts a statement of its own, so the
/// brace that opened the block closes several statements on, and the
/// parameters are bound until it does.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[derive(Debug, Default)]
pub struct Blocks<'a> {
    open: Vec<(i32, Vec<&'a str>)>,
    depth: i32,
}

impl<'a> Blocks<'a> {
    /// METHOD: Every parameter of the blocks still open.
    pub fn names(&self) -> impl Iterator<Item = &'a str> + '_ {
        self.open
            .iter()
            .flat_map(|(_, names)| names.iter().copied())
    }

    /// METHOD: Follow the braces of one statement, opening a block at
    /// a brace that stands against an arrow and closing it at the
    /// brace that matches.
    ///
    /// A brace with no partner cannot take the count below zero,
    /// because a count below zero would close a block at the wrong
    /// brace from then on.
    pub fn read(&mut self, stmt: &'a [Tok]) {
        for (i, tok) in stmt.iter().enumerate() {
            match tok.text.as_str() {
                "{" => {
                    self.depth += 1;

                    if i > 0 && stmt[i - 1].text == "=>" {
                        self.open.push((self.depth, params_before(stmt, i - 1)));
                    }
                }
                "}" => {
                    if self.open.last().is_some_and(|(at, _)| *at == self.depth) {
                        self.open.pop();
                    }

                    self.depth = (self.depth - 1).max(0);
                }
                _ => {}
            }
        }
    }

    /// METHOD: Forget every block. A body holds its lambdas whole, so
    /// where a body starts or ends none is open, and one a broken line
    /// never closed stops binding its names there.
    pub fn clear(&mut self) {
        self.open.clear();
        self.depth = 0;
    }
}

/// FUNCTION: The name a statement declares and the type it gives it,
/// as `var x: Foo` states one and `var x = Foo.new()` implies one. The
/// type is empty where the declaration gives none, because knowing a
/// name is a variable at all is what tells it from a class name.
/// FUNCTION: Which of the three declaring words opened a statement.
///
/// `strip_modifiers` removes `final` wherever it stands, so the word
/// cannot be read back from the stripped list and has to be taken
/// from the tokens.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
fn declaring_word(stmt: &[Tok]) -> Option<&str> {
    stmt.iter()
        .take(4)
        .map(|t| t.text.as_str())
        .find(|w| matches!(*w, "var" | "const" | "final"))
}

fn declared_name(stmt: &[Tok]) -> Option<(String, String)> {
    let at = stmt
        .iter()
        .take(4)
        .position(|t| matches!(t.text.as_str(), "var" | "const" | "final"))?;
    let rest = &stmt[at + 1..];

    if let Some((name, ty)) = annotated(rest) {
        return Some((name, ty));
    }

    let name = rest.first().filter(|t| t.kind == TokKind::Ident)?;

    // `var menu = Menu.new()` says as much as a declared type does.
    if let Some(eq) = rest.iter().position(|t| t.text == "=") {
        let class = rest.get(eq + 1).filter(|t| t.kind == TokKind::Ident);
        if let Some(class) = class {
            if rest.get(eq + 2).map(|t| t.text.as_str()) == Some(".")
                && rest.get(eq + 3).map(|t| t.text.as_str()) == Some("new")
            {
                return Some((name.text.clone(), class.text.clone()));
            }
        }
    }

    Some((name.text.clone(), String::new()))
}

/// FUNCTION: The index of every name a declaration binds by unpacking
/// a list, as `var [a, b: number; rest] = F()` binds three. Empty for
/// a declaration of one name and for a statement that declares none.
///
/// The first name of each part is the one it declares, and a type may
/// follow it. A semicolon stands before the name that takes what is
/// left of the list.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
pub fn unpacked_at(stmt: &[Tok]) -> Vec<usize> {
    let word = stmt
        .iter()
        .take(4)
        .position(|t| matches!(t.text.as_str(), "var" | "const" | "final"));

    let Some(open) = word.map(|at| at + 1) else {
        return Vec::new();
    };

    if stmt.get(open).map(|t| t.text.as_str()) != Some("[") {
        return Vec::new();
    }

    let close = closing(stmt, open).unwrap_or(stmt.len());
    let mut out = Vec::new();
    let mut depth = 0i32;
    let mut fresh = true;

    for (i, tok) in stmt.iter().enumerate().take(close).skip(open + 1) {
        match tok.text.as_str() {
            "(" | "[" | "{" | "<" => depth += 1,
            ")" | "]" | "}" | ">" => depth -= 1,
            ">>" => depth -= 2,
            "," | ";" if depth == 0 => fresh = true,
            _ if fresh && tok.kind == TokKind::Ident => {
                out.push(i);
                fresh = false;
            }
            _ => {}
        }
    }

    out
}

/// FUNCTION: The name and type of an annotated declaration, `x: Foo`,
/// taking the outermost type of `list<Foo>` as the type itself.
fn annotated(toks: &[Tok]) -> Option<(String, String)> {
    let name = toks.first().filter(|t| t.kind == TokKind::Ident)?;
    if toks.get(1).map(|t| t.text.as_str()) != Some(":") {
        return None;
    }
    let ty = toks.get(2).filter(|t| t.kind == TokKind::Ident)?;

    Some((name.text.clone(), ty.text.clone()))
}

/// FUNCTION: The index of the bracket closing the one at a position.
fn closing(stmt: &[Tok], open: usize) -> Option<usize> {
    let mut depth = 0i32;

    for (i, tok) in stmt.iter().enumerate().skip(open) {
        match tok.text.as_str() {
            "(" | "[" | "{" => depth += 1,
            ")" | "]" | "}" => {
                depth -= 1;
                if depth == 0 {
                    return Some(i);
                }
            }
            _ => {}
        }
    }

    None
}

/// FUNCTION: The container a statement opens, as the keyword that
/// opens it and the name it gives it.
fn opens_container<'a>(words: &'a [&'a str]) -> Option<(&'a str, &'a str)> {
    let rest = match words.split_first() {
        Some((&"export", rest)) => rest,
        _ => words,
    };
    let rest = match rest.split_first() {
        Some((&"abstract", rest)) => rest,
        _ => rest,
    };

    match rest.split_first() {
        Some((keyword @ &("class" | "enum" | "interface"), rest)) => {
            rest.first().map(|name| (*keyword, *name))
        }
        _ => None,
    }
}

/// FUNCTION: True when a statement opens a function body.
///
/// An abstract method is declared without one, and no `enddef`
/// follows it, so a depth raised for it would swallow the fields
/// declared after it.
fn is_def(stmt: &[Tok], words: &[&str]) -> bool {
    let Some(at) = words.iter().position(|w| *w == "def") else {
        return false;
    };

    // Only a modifier before `def` can make it abstract. A parameter
    // or a default value may be called anything, `abstract` among
    // them, and says nothing about whether a body follows.
    !words[..at].contains(&"abstract") && stmt.iter().any(|t| t.text == "(")
}

/// FUNCTION: The identifiers of a statement, in order.
fn idents(stmt: &[Tok]) -> Vec<&str> {
    stmt.iter()
        .filter(|t| t.kind == TokKind::Ident)
        .map(|t| t.text.as_str())
        .collect()
}

/// FUNCTION: The type of the receiver of a member access at a
/// position, or none when nothing in scope gives it one.
///
/// The receiver may be a name, `this`, a chain through a field of
/// `this`, or the result of a constructor, as `Menu.new(x).Open()` is.
pub fn recv_type(
    stmt: &[Tok],
    at: usize,
    owner: Option<&str>,
    locals: &Locals,
    types: &Types,
) -> Option<String> {
    if at < 2 || stmt[at - 1].text != "." {
        return None;
    }

    let before = &stmt[at - 2];

    // `Menu.new(x).Open()`: step back over the call to what built it.
    if before.text == ")" {
        let open = opening(stmt, at - 2)?;
        if stmt.get(open.wrapping_sub(1)).map(|t| t.text.as_str()) == Some("new")
            && stmt.get(open.wrapping_sub(2)).map(|t| t.text.as_str()) == Some(".")
        {
            let class = stmt.get(open.wrapping_sub(3))?;
            if class.kind == TokKind::Ident {
                return Some(class.text.clone());
            }
        }
        return None;
    }

    if before.kind != TokKind::Ident {
        return None;
    }

    // `this.field.Method()`: the field's own declared type.
    if at >= 4 && stmt[at - 3].text == "." && stmt[at - 4].text == "this" {
        return types.field(owner?, &before.text).map(str::to_string);
    }

    if before.text == "this" {
        return owner.map(str::to_string);
    }

    if let Some(ty) = locals.get(&before.text) {
        return (!ty.is_empty()).then(|| ty.to_string());
    }

    // A name the body declared with no type says nothing, while a name
    // it never declared is a class, an enum, or an import alias, which
    // names itself.
    if locals.holds(&before.text) {
        return None;
    }

    if let Some(ty) = types.global(&before.text) {
        return (!ty.is_empty()).then(|| ty.to_string());
    }

    Some(before.text.clone())
}

/// FUNCTION: The index of the bracket opening the one at a position.
fn opening(stmt: &[Tok], close: usize) -> Option<usize> {
    let mut depth = 0i32;

    for i in (0..=close).rev() {
        match stmt[i].text.as_str() {
            ")" | "]" | "}" => depth += 1,
            "(" | "[" | "{" => {
                depth -= 1;
                if depth == 0 {
                    return Some(i);
                }
            }
            _ => {}
        }
    }

    None
}
