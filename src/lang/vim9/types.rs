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
        let mut in_def = false;

        for stmt in stmts {
            let words: Vec<&str> = idents(stmt);

            match words.first().copied() {
                Some("endclass" | "endenum" | "endinterface") => {
                    owner = None;
                    in_def = false;
                    continue;
                }
                Some("enddef") => {
                    in_def = false;
                    continue;
                }
                _ => {}
            }

            if let Some(name) = opens_container(&words) {
                owner = Some(name.to_string());
                in_def = false;
                continue;
            }

            if is_def(stmt, &words) {
                in_def = true;
                continue;
            }

            if in_def {
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

/// The types in scope inside one function body: its parameters and the
/// variables it declares. A body's locals say nothing about any other
/// body, so this is rebuilt at each `def`.
#[derive(Debug, Clone, Default)]
pub struct Locals {
    vars: HashMap<String, String>,
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
        for param in stmt[open + 1..close].split(|t| t.text == ",") {
            if let Some((name, ty)) = annotated(param) {
                locals.vars.insert(name, ty);
            } else if let Some(name) = param.first().filter(|t| t.kind == TokKind::Ident) {
                locals.vars.entry(name.text.clone()).or_default();
            }
        }

        locals
    }

    /// METHOD: Record the type of a variable a statement declares,
    /// whether it states one or builds one with a constructor.
    pub fn declare(&mut self, stmt: &[Tok]) {
        if let Some((name, ty)) = declared_name(stmt) {
            self.vars.insert(name, ty);
        }
    }

    /// METHOD: The type of a name in this body, where it has one.
    pub fn get(&self, name: &str) -> Option<&str> {
        self.vars.get(name).map(String::as_str)
    }

    /// METHOD: True when this body declares the name at all, which is
    /// what tells an untyped variable from a class name.
    pub fn holds(&self, name: &str) -> bool {
        self.vars.contains_key(name)
    }
}

/// FUNCTION: The name a statement declares and the type it gives it,
/// as `var x: Foo` states one and `var x = Foo.new()` implies one. The
/// type is empty where the declaration gives none, because knowing a
/// name is a variable at all is what tells it from a class name.
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

/// FUNCTION: The name of the container a statement opens.
fn opens_container<'a>(words: &'a [&'a str]) -> Option<&'a str> {
    let rest = match words.split_first() {
        Some((&"export", rest)) => rest,
        _ => words,
    };
    let rest = match rest.split_first() {
        Some((&"abstract", rest)) => rest,
        _ => rest,
    };

    match rest.split_first() {
        Some((&("class" | "enum" | "interface"), rest)) => rest.first().copied(),
        _ => None,
    }
}

/// FUNCTION: True when a statement opens a function body.
fn is_def(stmt: &[Tok], words: &[&str]) -> bool {
    words.contains(&"def") && stmt.iter().any(|t| t.text == "(")
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
