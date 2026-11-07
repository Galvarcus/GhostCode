//! The program the front-end suite runs in place of the binary, where the
//! platform cannot start a script as one.
//!
//! The contract is the one tests/stub/ghostcode holds: write every
//! argument to $GHOSTCODE_STUB_ARGS, one per line; print
//! $GHOSTCODE_STUB_OUT; exit with $GHOSTCODE_STUB_EXIT. The front end
//! starts the binary with the list form of systemlist(), which starts a
//! program directly rather than through a shell, so a script cannot stand
//! in for it on Windows. The job that runs the suite there compiles this
//! with rustc. Nothing in the crate builds it, because cargo reads no
//! subdirectory of tests/.
//!
//! License: GNU GPL 3.0

use std::env;
use std::fs;
use std::io::Write;
use std::process::ExitCode;

fn main() -> ExitCode {
    let args: Vec<String> = env::args().skip(1).collect();

    // The suite reads this file to prove what reached the binary, so one
    // argument holding a space must stay one line, as it does here.
    if let Ok(path) = env::var("GHOSTCODE_STUB_ARGS") {
        if !path.is_empty() {
            let mut text = args.join("\n");
            text.push('\n');
            let _ = fs::write(path, text);
        }
    }

    let out = env::var("GHOSTCODE_STUB_OUT").unwrap_or_default();
    let mut stdout = std::io::stdout();
    let _ = stdout.write_all(out.as_bytes());
    let _ = stdout.flush();

    let code = env::var("GHOSTCODE_STUB_EXIT")
        .ok()
        .and_then(|v| v.parse::<u8>().ok())
        .unwrap_or(0);

    ExitCode::from(code)
}
