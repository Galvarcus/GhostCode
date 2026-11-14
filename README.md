# Ghostcode

<!-- vimdoc-ignore-start -->

[![Vim](https://img.shields.io/badge/vim-9.2%2B-019733)](https://www.vim.org/)
[![License](https://img.shields.io/badge/license-GPL--3.0-blue)](https://www.gnu.org/licenses/gpl-3.0.en.html)
[![CI](https://github.com/Galvarcus/GhostCode/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/Galvarcus/GhostCode/actions/workflows/ci.yml)

<!-- vimdoc-ignore-end -->

Ghostcode is an analyzer for unreferenced code in Vim9 script, with
Vim plugin functionality. It scans a project for functions, methods,
classes, fields, enum values, and script-level variables, then reports
every one that nothing in the project ever calls or reads.

The analyzer is a command line program. The Vim plugin runs it and puts
the findings in the quickfix list.

<!-- vimdoc-ignore-start -->

## Requirements

- The `ghostcode` binary, for Linux, macOS, or Windows. See
  Installation.
- For the Vim plugin: Vim 9.2 or later, and
  [Logger](https://github.com/Galvarcus/Logger), which shows
  Ghostcode's messages.

## Installation

### The binary

Download the binary for your platform from the
[latest release](https://github.com/Galvarcus/GhostCode/releases/latest),
check it against the `.sha256` file beside it, and put it on your
`PATH`:

```bash
curl -fsSLO https://github.com/Galvarcus/GhostCode/releases/latest/download/ghostcode-x86_64-unknown-linux-gnu
curl -fsSLO https://github.com/Galvarcus/GhostCode/releases/latest/download/ghostcode-x86_64-unknown-linux-gnu.sha256
shasum -a 256 -c ghostcode-x86_64-unknown-linux-gnu.sha256
install -m 755 ghostcode-x86_64-unknown-linux-gnu ~/.local/bin/ghostcode
```

| Asset | Runs on |
| --- | --- |
| `ghostcode-x86_64-unknown-linux-gnu` | Linux on x86-64, with glibc 2.34 or later: Ubuntu 22.04, Debian 12, RHEL 9, and the later releases of each |
| `ghostcode-x86_64-apple-darwin` | macOS 10.12 or later, on Intel |
| `ghostcode-aarch64-apple-darwin` | macOS 11.0 or later, on Apple silicon |
| `ghostcode-x86_64-pc-windows-msvc.exe` | Windows 10 or later, on x86-64 |

On Windows, put the `.exe` on your `PATH`, or name it with its
extension in `g:ghostcode_bin`.

Releases after v0.1.0 carry a build provenance attestation, which
names the workflow and the commit that produced an asset. v0.1.0 has
none:

```bash
gh attestation verify ghostcode-x86_64-unknown-linux-gnu -R Galvarcus/GhostCode
```

To build it instead, with a Rust toolchain:

```bash
cargo install ghostcode
```

### The Vim plugin

Install Ghostcode and Logger with your plugin manager.

**vim-plug**

```vim
Plug 'Galvarcus/Logger'
Plug 'Galvarcus/GhostCode'
```

**Native package**

```bash
git clone https://github.com/Galvarcus/Logger.git \
  ~/.vim/pack/vendor/start/Logger
git clone https://github.com/Galvarcus/GhostCode.git \
  ~/.vim/pack/vendor/start/GhostCode
```

<!-- vimdoc-ignore-end -->

The plugin looks for the binary at `g:ghostcode_bin`, then on `$PATH`,
then in a `bin/` directory of its own. Create that directory and put a
release asset in it, named `ghostcode`, or `ghostcode.exe` on Windows,
to keep the binary beside the plugin. When the plugin finds no binary,
it says so through Logger and names each place it looked.

## Usage

<!-- vimdoc-ignore-start -->

```bash
ghostcode [path]
```

`path` is the root of the project to scan. It defaults to the working
directory. The report goes to standard output as JSON:

```json
{
  "schema": 1,
  "root": "/path/to/project",
  "summary": { "symbols": 412, "ghost": 1, "local": 0, "unplaced_names": 7 },
  "findings": [
    {
      "class": "ghost",
      "kind": "function",
      "name": "AddSeparator",
      "file": "autoload/util.vim",
      "line": 15,
      "col": 1,
      "lang": "vim9"
    }
  ]
}
```

`--format=text` prints one line per finding instead:

```text
autoload/util.vim:15:1:[ghost] function AddSeparator
```

`schema` states the shape of the JSON. It rises when a change would
break a reader, so a front end that meets a number it does not know can
say so rather than guess. The counts in `summary` are diagnostics
rather than contract: nothing is derived from them, and one may be
renamed without the schema rising.

<!-- vimdoc-ignore-end -->

### In Vim

Ghostcode adds one command:

```vim
:GhostCode [path]
```

`path` is the root of the project to scan. It defaults to the working
directory of Vim.

It puts the findings in the quickfix list, opens the list when it finds
any, and shows a summary through Logger:

```text
Ghostcode - ghostcode.vim - Report: 23 symbols, 7 ghost
```

Each entry names the kind of symbol, its name, its file, and its line:

```text
autoload/util.vim|16 col 1| [ghost] function TrulyDeadFunction
autoload/util.vim|37 col 1| [ghost] method DeadMethod
autoload/util.vim|58 col 1| [ghost] variable g_never_read
```

Logger reads its options for Ghostcode from variables named
`g:logger_ghostcode_<option>`. See the Logger README for each option.

<!-- vimdoc-ignore-start -->

### In CI

Run the binary and fail the build on any finding:

```bash
ghostcode --format=text . | tee findings.txt
test ! -s findings.txt
```

<!-- vimdoc-ignore-end -->

## Settings

### `ghostcode.toml`

A project states its own settings in `ghostcode.toml`, in its root:

```toml
# Whether an exported symbol is public API, so that nothing reports it.
exports_are_api = false

# Paths to leave out, beyond the ones git ignores.
ignore = ["deps/**", "vendor/**"]

# Files that are entry points, whose top-level code needs no caller.
entry = ["tools/build.vim"]

# Scoped variables written for a reader outside the project.
external = ["g:tlinks_*"]

# The finding classes to report beyond the default.
[findings]
locals = true
globals = true
buffer_vars = true
window_vars = true
tab_vars = true
```

`exports_are_api` is true by default. Ghostcode then treats an exported
symbol as public API and never reports it. Vim9 cannot export a method
or a field by itself, so every method and field of an exported class
counts as exported too, unless its name starts with an underscore.

Set it to false for a plugin whose exports serve only its own files, as
in an application. Ghostcode then reports an export that nothing in the
project uses, like any other symbol.

`findings.locals` is false by default. Set it to true to report a
`var` or a `const` of a function body that nothing in that body reads.
An assignment is not a read, so a local the code only writes is
reported too. A parameter and a `for` variable are left alone.

The finding reads `[local]` rather than `[ghost]`, so a build that
counts the ghosts counts none of these.

`findings.globals`, `findings.buffer_vars`, `findings.window_vars`,
and `findings.tab_vars` are false by default. Each one reports the
variables of one scope, `g:`, `b:`, `w:`, or `t:`, that the project
writes and nothing reads:

```text
plugin/example.vim:12:1:[ghost] variable g:example_width
```

These rules decide what counts as a read:

- `g:name` in code, and `g:name` inside any string.
- `get()` and `has_key()` on a scope, `exists()`, and the
  `getbufvar()` family. `setbufvar()` and its kin are writes.
- A name held in a `const` of the same file whose value is one string.
- A name built at run time, as `get(g:, $'example_{kind}_width')`,
  which reads every variable that its fixed parts fit.

These do not count as a read:

- A second write.
- A read in the command that writes the variable. The `get()` of
  `g:name = get(g:, 'name', default)` reads what the user set, so a
  setting that no other line reads is reported.
- A read in code that nothing reaches.

The finding names the write that takes the user's value where one
exists, and otherwise the first write by path and line. Ghostcode
reports no variable that the Vim help documents, such as
`b:current_syntax`.

The finding reads `[ghost]`, so a build that counts the ghosts
enforces it once the flag is on.

A line that uses a scope with no fixed name, such as `keys(g:)` or
`get(g:, name)`, reads every variable of that scope. Ghostcode then
reports none for the scope and says so on stderr, with the file and
the line:

```text
ghostcode: autoload/example.vim:35: every g: variable counts as read from this line, so none is reported
```

In Vim the same message goes to the log and not to the quickfix list.

`external` lists the scoped variables that the project writes for
another plugin to read. Give the full spelling. A `*` stands for any
run of characters. Ghostcode never reports a variable listed there.

<!-- vimdoc-ignore-start -->

### Command line

A flag overrides the file:

| Flag | Effect |
| --- | --- |
| `--format=json`, `--format=text` | The output form. JSON is the default. |
| `--exports-are-api true`, `--exports-are-api false` | Override `exports_are_api`. |
| `--no-ignore` | Read every file, including the ones git ignores. |
| `--locals true`, `--locals false` | Override `findings.locals`. |
| `--globals true`, `--globals false` | Override `findings.globals`. |
| `--buffer-vars true`, `--buffer-vars false` | Override `findings.buffer_vars`. |
| `--window-vars true`, `--window-vars false` | Override `findings.window_vars`. |
| `--tab-vars true`, `--tab-vars false` | Override `findings.tab_vars`. |

<!-- vimdoc-ignore-end -->

### Vim

| Variable | Effect |
| --- | --- |
| `g:ghostcode_bin` | The binary to run, for a copy that is neither on `$PATH` nor in the plugin's `bin/` directory. |
| `g:ghostcode_exports_are_api` | Override `exports_are_api`. The plugin passes the flag only when you set this, so that a project's `ghostcode.toml` governs where you do not. |
| `g:ghostcode_locals` | Override `findings.locals`. Passed on the same terms. |
| `g:ghostcode_globals` | Override `findings.globals`. Passed on the same terms. |
| `g:ghostcode_buffer_vars` | Override `findings.buffer_vars`. Passed on the same terms. |
| `g:ghostcode_window_vars` | Override `findings.window_vars`. Passed on the same terms. |
| `g:ghostcode_tab_vars` | Override `findings.tab_vars`. Passed on the same terms. |

## What Ghostcode scans

Ghostcode reads the files git does not ignore, whether git tracks them
or not. Outside a repository nothing is ignored and every file is
read. It stops at the project root and follows no symlink out of it,
because a finding outside the root is one you cannot act on. It skips
hidden directories, as Vim's own `globpath` does; name a file in
`entry` to scan one anyway.

## What Ghostcode detects

- `def` and `export def`
- `class` and `export class`, including `extends` and `implements`
- `enum` and `export enum`, and enum values (`Color.Red`)
- `interface` and `export interface` declarations
- class methods, static methods, and fields
- module-level script variables and class fields
- a `var` or a `const` of a function body that nothing in that body
  reads, where you ask for the class, see Settings
- type annotations (`var x: Foo`, `def F(): Foo`, `list<Foo>`)
- direct calls (`Foo()`), method calls (`Foo.Bar()`, `this.Method()`),
  and calls through a locally-typed variable or parameter, including a
  two-level field-then-method chain on `this` (`this.field.Method()`)
- a method called directly on a constructor result
  (`Foo.new(args).Bar()`)
- bare funcref and value usage of a known symbol (`var Ref = Foo`,
  `timer_start(1000, Foo)`, `{callback: Foo}`)
- names inside string interpolation (`$'see {LABEL} here'`)
- `call()`, `function()`, `execute()`, and `exists()`, where the target
  is a string literal or bare identifier
- a name that any other string holds, where the project declares a
  symbol of that name, because Vim evaluates text in places a parser
  cannot see: the right-hand side of a mapping, a `feedkeys` sequence,
  a substitution opening with `\=`
- every `import` form: relative paths, `import autoload`, and named
  imports (`import {Foo} from '...'`)
- exported symbols, treated as public API and never reported as dead
  unless you turn that off, see Settings
- the classic `plugin#Function()` autoload calling convention
- top-level code in scripts that Vim sources directly (`plugin/`,
  `ftplugin/`, `ftdetect/`, `syntax/`, `indent/`, `compiler/`,
  `colors/`, `keymap/`, `lang/`, and their `after/` copies) and in
  `tests/`, all treated as entry points that need no call site

## What Ghostcode doesn't detect

- a parameter or a `for` variable that nothing reads. Only a `var` or a
  `const` of a function body is reported, and only where you ask for
  the class: a parameter is part of a signature that a caller outside
  the project may hold to
- dynamic dispatch built from string concatenation, computed
  indices, or anything else that isn't a literal identifier or string
- method calls on a variable with no declared or inferable type. When
  a variable's type can't be determined, Ghostcode falls back to the
  class members of that name across the project. When several classes
  declare the name, it counts every one of them as used. A name behind
  a dot never counts as a use of a function or a variable of that name
- calls into a file outside the project root. An import that names
  another plugin, or a copy of one under a directory such as `deps/`,
  is not followed, so nothing in that file is counted as used through
  it
- a script variable or a field that the code only writes and never
  reads. A write counts as a use there. Inside a function body it does
  not, so a local the code only assigns to is reported with the other
  locals
- a legacy `function` that nothing calls. Only a `def` is a symbol. A
  call from the body of a legacy function still counts as a use

Ghostcode is conservative by design: anything it can't prove is
unreferenced is left alone rather than reported.

<!-- vimdoc-ignore-start -->

## Development

Run every check with Logger reachable:

```bash
LOGGER=/path/to/Logger tools/check
```

It runs `cargo fmt`, `cargo clippy`, `cargo test`, a release build, the
timing ceiling, the front-end tests under Vim, Ghostcode on its own
code, and `actionlint`. It prints one line per check.

`cargo test` covers the analyzer, including the parity suite, which
compares what Ghostcode reports for four committed corpora against what
the Vim9 analyzer it replaces reported for them. `tests/harness.vim`
covers the Vim front end, against a stub binary, so it needs no release
build:

```bash
vim -es -u NONE -N --cmd 'set rtp+=.,/path/to/Logger' \
  -c 'runtime plugin/ghostcode.vim' \
  -c 'source tests/harness.vim' -c 'quit'
cat tests/results.txt
```

The suite runs a stub in place of the binary. On Windows that stub is a
program compiled from `tests/stub/ghostcode.rs`, because the front end
starts the binary directly rather than through a shell, so build it
first:

```bash
rustc -O tests/stub/ghostcode.rs -o tests/stub/ghostcode.exe
```

The file reads `All tests passed` when every test passes. A test the
running Vim cannot meet the conditions of, such as a patch it lacks, is
skipped rather than failed, and the file counts and names each skip
above the verdict. Read those names: a skip is a test that did not run.

`doc/ghostcode.txt` is generated from this README by
`.github/workflows/vimdoc.yml`. Edit the README, not the help file.

`tools/survey` clones the Vim9 plugins of other projects that
`tools/survey.txt` lists, scans each, and prints a table of the counts.
The findings and the unplaced names of each scan go to
`target/survey/report`, for evaluation. No check runs it, and
`tools/survey --clean` removes what it wrote.

<!-- vimdoc-ignore-end -->

## License

GNU GPL 3.0
