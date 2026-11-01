# Ghostcode

Ghostcode finds unreferenced code in Vim9 plugins. The analysis is a
Rust binary; the Vim plugin runs it and fills the quickfix list.

## Repositories

Ghostcode is proved against real projects, not synthetic ones. Bartleby
and its Logger dependency are the test cases, and copies of their Vim
scripts are committed under `tests/fixtures/corpora/`. Bartleby's CI
runs Ghostcode, so a change in what Ghostcode reports can break that
build.

## Skills

- `rust-cli` for anything under `src/` or `tests/*.rs`, and for
  `Cargo.toml`.
- `vim9script-plugin` for `plugin/`, `autoload/`, and `tests/*.vim`.
- `code-comments` for every comment in either language.
- `github-markdown-style` for `README.md` and this file.

## Preferences

- The subject of a commit states the problem, not the fix. See Commits.
- Never hard-code a value. Name it once and use the name. In Vim
  scripts the plugin name comes from `PLUGIN_NAME` in
  `autoload/ghostcode/log.vim`; in Rust it comes from `NAME` in
  `src/lib.rs`.
- Do not edit `doc/ghostcode.txt`. It is generated from `README.md` by
  `.github/workflows/vimdoc.yml` on a push to `main`.
- Do not edit `tests/fixtures/expected/`. Those files record what the
  Vim9 analyzer reported before it was deleted, and nothing can
  recreate them. A change to one needs a reason in the commit message.

## Issues

`fixes:` names the issue a commit closes and `related:` names one that
bears on it. Align the values and end them without a period.

## Commits

A commit message states the problem the commit fixes, in the format
that Vim uses:

```text
subject states the problem

Problem:  Full sentence restating the subject.
Solution: Short description of the fix, ending with the author's name in
          parentheses.

Prose for a longer account of the problem and the fix. No bullet points.

fixes:   #NNNN
related: #NNNN

Assisted-by: Claude Opus 5
```

Keep the subject to 72 characters, in lower case, with no trailing
period. Wrap the prose at 78 columns. `Assisted-by: Claude Opus 5` is
required when Claude wrote any of the change. A `prepare-commit-msg`
hook adds `Signed-off-by:`, so never write one by hand and never pass
`-s`. The hook lives in `.git/hooks`, which git never clones, so a
fresh checkout needs it installed again.

Always ask before pushing.

## Architecture

- `src/main.rs` parses arguments, calls one function, and maps an error
  to an exit status. Everything testable lives under `src/lib.rs`.
- `src/report/mod.rs` holds `analyze`, which is the whole pipeline:
  discover the files, scan each in its own language, turn the project's
  text into references, resolve, walk, report.
- `src/resolve.rs` and `src/reach.rs` know no language. Every language
  fact lives behind the `Lang` trait in `src/lang/mod.rs`. That line is
  what makes a second language a module rather than a rewrite.
- `src/lang/vim9/` holds the Vim9 lexer, parser, type tracking, and
  rules. No tree-sitter grammar parses Vim9: `tree-sitter-vim` covers
  legacy Vimscript alone, with no rule for `vim9script`, `def`,
  `class`, `interface`, or `enum`.
- Every lookup in `src/resolve.rs` is an index lookup. The analyzer
  this replaced walked every symbol for every reference, so its cost
  grew with the square of the project: 106 seconds for Bartleby against
  0.2 now. A change that walks the symbols again gives that back.
- `plugin/ghostcode.vim` defines the command and sets no defaults. A
  default assigned there cannot be told from a value the user chose,
  and would override a project's `ghostcode.toml` everywhere.
- Both Vim scripts guard on `v:version < 901`, where the
  `vim9script-plugin` skill states 902. The README and the release
  promise Vim 9.1, and the front end needs less of Vim than the deleted
  analyzer did, so raising the guard would drop a supported Vim.
- `autoload/ghostcode.vim` finds the binary, runs it, and fills the
  quickfix list. Every failure goes through Logger, never through
  `:throw`.
- The quickfix text, `[ghost] <kind> <name>` at column 1, sorted by
  file then line, is a contract. Bartleby's CI counts the lines that
  carry `[ghost]`.

## Verification

Run from the root of the repository, with Logger reachable.

| Check | Command | Passes when |
| --- | --- | --- |
| Everything | `LOGGER=/path/to/Logger tools/check` | it prints `every check passed` |
| Analyzer | `cargo test` | every test passes |
| Parity | `cargo test --test parity` | every corpus matches its fixture |
| Timing | `cargo test --release --test timing -- --nocapture` | the scan stays under the ceiling |
| Front end | `vim -es -u NONE -N --cmd 'set rtp+=.,deps/Logger' -c 'runtime plugin/ghostcode.vim' -c 'source tests/harness.vim' -c 'quit'` | `tests/results.txt` reads `All tests passed` |
| Self scan | `./target/release/ghostcode --format=text .` | it prints nothing |
| Workflows | `actionlint .github/workflows/*.yml` | no findings |

- The parity suite is the acceptance test of the port. A difference is
  either a defect here or a fault in the old analyzer, and neither is
  accepted without being read.
- To prove a test guards a change, break the change on purpose and
  confirm that a named test fails. The front-end suite needed this: a
  stale `tests/results.txt` once read as a pass while the suite was in
  fact aborting.
- A new Rust test goes in `tests/<subject>.rs`, or in a
  `#[cfg(test)] mod tests` at the end of the file it tests. A new Vim
  test goes in `tests/test_<area>.vim` and is registered in
  `tests/harness.vim`.
