//! The JSON form: the contract every front end reads.
//!
//! License: GNU GPL 3.0

use super::Report;

/// FUNCTION: The report as JSON, indented, because a person reads it
/// as often as a program does and a diff of it should be legible.
pub fn json(r: &Report) -> String {
    serde_json::to_string_pretty(r).unwrap_or_else(|_| String::from("{}"))
}
