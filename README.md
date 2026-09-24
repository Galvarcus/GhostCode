# Ghostcode

![Vim](https://img.shields.io/badge/vim-9.1%2B-019733)
![License](https://img.shields.io/badge/license-GPL--3.0-blue)

Ghostcode finds unreferenced code in Vim9 plugins. It scans a project
for functions, methods, classes, fields, enum values, and script-level
variables, then reports every one that nothing in the project ever
calls or reads.

## Requirements

Vim 9.1 or later, compiled with Vim9 script and class support.

## Installation

Ghostcode is a Vim plugin with a `plugin/` component and an
`autoload/` component. Install it with your plugin manager of choice.

**vim-plug**

```vim
Plug 'Galvarcus/ghostcode'
```

**Native package (Vim 8+)**

```bash
git clone https://github.com/Galvarcus/ghostcode.git \
  ~/.vim/pack/vendor/start/ghostcode
```

**lazy.nvim**

```lua
{ 'Galvarcus/ghostcode' }
```

## Usage

Ghostcode adds one command:

```vim
:GhostCode [path]
```

`path` is the root directory of the project to scan and supports
file completion. It defaults to the current working directory when
omitted.

Findings are reported in the quickfix list, which opens automatically
when Ghostcode finds anything:

```text
GhostCode: 23 symbols, 7 ghost, 3 unresolved
```

Each quickfix entry names the kind of symbol, its name, its file, and
its line:

```text
testplugin/autoload/util.vim|16 col 1| [ghost] function TrulyDeadFunction
testplugin/autoload/util.vim|37 col 1| [ghost] method DeadMethod
testplugin/autoload/util.vim|58 col 1| [ghost] variable g_never_read
```

### Running from the command line

To run Ghostcode headlessly, for example in CI, source its `plugin/`
script explicitly before invoking the command. `-u NONE` skips Vim's
normal startup, including the automatic loading that would otherwise
define `:GhostCode` on its own:

```bash
vim -u NONE -N -es \
  --cmd 'set rtp+=/path/to/ghostcode' \
  -c 'runtime plugin/ghostcode.vim' \
  -c 'GhostCode /path/to/project' \
  -c 'vim9cmd writefile(getqflist()->mapnew((_, i) => printf("%s:%d: %s", bufname(i.bufnr), i.lnum, i.text)), "ghostcode_results.txt")' \
  -c 'qa!'
```

## What Ghostcode detects

- `def` and `export def`
- `class` and `export class`, including `extends` and `implements`
- `enum` and `export enum`, and enum values (`Color.Red`)
- `interface` and `export interface` declarations
- class methods, static methods, and fields
- module-level script variables and class fields
- type annotations (`var x: Foo`, `def F(): Foo`, `list<Foo>`)
- direct calls (`Foo()`), method calls (`Foo.Bar()`, `this.Method()`),
  and calls through a locally-typed variable or parameter, including a
  two-level field-then-method chain on `this` (`this.field.Method()`)
- a method called directly on a constructor result
  (`Foo.new(args).Bar()`)
- bare funcref and value usage of a known symbol (`var Ref = Foo`,
  `timer_start(1000, Foo)`, `{callback: Foo}`)
- `call()`, `function()`, and `execute()`, where the target is a
  string literal or bare identifier
- every `import` form: relative paths, `import autoload`, and named
  imports (`import {Foo} from '...'`)
- exported symbols, treated as public API and never reported as dead
- the classic `plugin#Function()` autoload calling convention
- top-level code in `plugin/*.vim` and `tests/*.vim`, both treated as
  entry points invoked directly rather than requiring a call site

## What Ghostcode doesn't detect

- local variables declared inside a function body. Ghostcode analyzes
  reachability between module-level symbols, not local dead stores
- dynamic dispatch built from string concatenation, computed
  indices, or anything else that isn't a literal identifier or string
- method calls on a variable with no declared or inferable type. When
  a variable's type can't be determined, Ghostcode falls back to
  finding an unambiguous same-name match across the project, and
  reports nothing if that name isn't unique

Ghostcode is conservative by design: anything it can't prove is
unreferenced is left alone rather than reported.

## License

GNU GPL 3.0
