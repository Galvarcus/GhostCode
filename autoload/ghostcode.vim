vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif

var is_loaded: bool = true

# Plugin_Name: Ghostcode
# Runs the ghostcode binary and puts what it reports in the quickfix
# list. The analysis is the binary's; this script finds it, calls it,
# reads its JSON, and says through Logger what it could not do.
# License: GNU GPL 3.0

import autoload 'ghostcode/log.vim' as L

var log = L.New(expand('<sfile>:t'))

# The output shape this script can read. The binary states its own, and
# a higher one means a binary newer than this plugin, which is better
# said than guessed at.
const SCHEMA: number = 1

const BIN: string = 'ghostcode'
# The name of the file to run. Windows gives it an extension, and so
# does Cygwin, whose Vim answers no to win32. The places that name a
# file follow this: the copy beside the plugin, and the message that
# says where the plugin looked.
const EXE: string = BIN .. (has('win32') || has('win32unix') ? '.exe' : '')
const BIN_DIR: string = 'bin'
const SETTING_BIN: string = 'ghostcode_bin'
const SETTING_API: string = 'ghostcode_exports_are_api'
const SETTING_LOCALS: string = 'ghostcode_locals'
const SETTING_GLOBALS: string = 'ghostcode_globals'
const SETTING_BUFFER_VARS: string = 'ghostcode_buffer_vars'
const SETTING_WINDOW_VARS: string = 'ghostcode_window_vars'
const SETTING_TAB_VARS: string = 'ghostcode_tab_vars'
const FLAG_FORMAT: string = '--format=json'
# The patch where system() and systemlist() began to take the command
# as a list. This plugin supports Vim 9.1, which has no such form.
const PATCH_ARGV: string = 'patch-9.2.0250'
const FLAG_API: string = '--exports-are-api'
const FLAG_LOCALS: string = '--locals'
const FLAG_GLOBALS: string = '--globals'
const FLAG_BUFFER_VARS: string = '--buffer-vars'
const FLAG_WINDOW_VARS: string = '--window-vars'
const FLAG_TAB_VARS: string = '--tab-vars'

const MSG_NO_BIN: string = 'no %s found. Looked at g:%s, then $PATH, then %s. Install it from the project''s releases, or build it with `cargo install %s`.'
const MSG_FAILED: string = '%s failed (status %d): %s'
const MSG_NOT_JSON: string = '%s did not report JSON: %s'
const MSG_SCHEMA: string = '%s reports schema %d, and this plugin reads %d. Update the plugin.'
const MSG_SUMMARY: string = '%d symbols, %d ghost'
const MSG_SKIPPED: string = '%s skipped, %s'
const MSG_NOTE: string = '%s:%d reads every %s variable, so none is reported'

# FUNCTION: Scan path, or the working directory, and put every finding
# in the quickfix list.
export def Run(path: string = ''): void
  # A full path ends with the separator of the platform, which the
  # quickfix paths are built without. A root directory is its own
  # separator, so that one is kept: dropping it passed no path at all.
  var root = fnamemodify(empty(path) ? getcwd() : path, ':p')
    ->substitute('\([^:\\/]\)[\\/]\+$', '\1', '')
  var bin = Bin()

  if empty(bin)
    log.Error(printf(MSG_NO_BIN, EXE, SETTING_BIN, Bundled(), BIN))
    return
  endif

  var out = Output(Cmd(bin, root))

  if v:shell_error != 0
    log.Error(printf(MSG_FAILED, BIN, v:shell_error, join(out, ' ')))
    return
  endif

  var report = Parse(join(out, "\n"))

  if empty(report)
    return
  endif

  Report(root, report)
enddef

# FUNCTION: The binary to run: the setting, then $PATH, then the copy
# beside this plugin, which the user fills from a release asset.
# Each answer is compared with 1, because executable() also returns
# -1, for a name it cannot decide about, which Vim9 refuses to read as
# a condition. An empty $PATH is enough to see it.
def Bin(): string
  var set = get(g:, SETTING_BIN, '')

  if !empty(set) && executable(set) == 1
    return set
  endif

  if executable(EXE) == 1
    # The path the search found, rather than the bare name. A bare
    # name is searched for again by whatever runs it, and on Windows
    # that search reaches the working directory first, where a copy
    # inside the project being scanned would win.
    return exepath(EXE)
  endif

  var bundled = Bundled()

  return executable(bundled) == 1 ? bundled : ''
enddef

# FUNCTION: Where a copy of the binary sits inside the plugin.
def Bundled(): string
  return fnamemodify(expand('<script>'), ':h:h') .. $'/{BIN_DIR}/{EXE}'
enddef

# FUNCTION: Add flag to cmd for a setting the user set, and nothing
# for one they did not, so that a project's ghostcode.toml is not
# overridden from here by a default nobody chose.
#
# The value is whatever the user wrote, and Vim9 reads only 0 and 1 as
# a condition. empty() takes any type, so a 2 or a word is passed on
# rather than thrown out of the scan.
def AddSetting(cmd: list<string>, setting: string, flag: string): void
  if !exists($'g:{setting}')
    return
  endif

  add(cmd, flag)
  add(cmd, empty(get(g:, setting)) ? 'false' : 'true')
enddef

# FUNCTION: The command to run, as a list, so that no path needs
# quoting and a folder whose name holds a space still scans.
def Cmd(bin: string, root: string): list<string>
  var cmd = [bin, FLAG_FORMAT]

  AddSetting(cmd, SETTING_API, FLAG_API)
  AddSetting(cmd, SETTING_LOCALS, FLAG_LOCALS)
  AddSetting(cmd, SETTING_GLOBALS, FLAG_GLOBALS)
  AddSetting(cmd, SETTING_BUFFER_VARS, FLAG_BUFFER_VARS)
  AddSetting(cmd, SETTING_WINDOW_VARS, FLAG_WINDOW_VARS)
  AddSetting(cmd, SETTING_TAB_VARS, FLAG_TAB_VARS)
  add(cmd, root)

  return cmd
enddef

# FUNCTION: What the binary printed. A list of arguments keeps each
# one whole, with no shell to quote for, and Vim takes a list only
# from the patch above. Before it, every argument is quoted here and
# the shell is asked to run the line.
#
# A command that prints nothing gets an empty String back from
# systemlist() and not an empty list, and join() refuses a String, so
# what is not a list is answered as no lines at all.
# REFERENCE: https://github.com/Galvarcus/GhostCode/issues/46
def Output(cmd: list<string>): list<string>
  var out: any

  if has(PATCH_ARGV)
    out = systemlist(cmd)
  else
    out = systemlist(cmd->mapnew((_, a) => shellescape(a))->join(' '))
  endif

  return type(out) == v:t_list ? out : []
enddef

# FUNCTION: The report the binary printed, or an empty dictionary when
# it cannot be read, having said why.
def Parse(text: string): dict<any>
  var report: dict<any>

  try
    report = json_decode(text)
  catch
    log.Error(printf(MSG_NOT_JSON, BIN, v:exception))
    return {}
  endtry

  # The schema is a number in every report the binary writes, and
  # comparing anything else with one throws.
  if type(report) != v:t_dict || !has_key(report, 'schema')
      || type(report.schema) != v:t_number
    log.Error(printf(MSG_NOT_JSON, BIN, text))
    return {}
  endif

  if report.schema > SCHEMA
    log.Error(printf(MSG_SCHEMA, BIN, report.schema, SCHEMA))
    return {}
  endif

  return report
enddef

# FUNCTION: Put the findings in the quickfix list and say what was
# found. A path comes back relative to the root, and is joined to it
# again here, so that the list reads as it always has.
#
# Logger names the function it was called from in every line the user
# reads, so this name is part of what the summary says. It states what
# the user is being told, not how the list is built.
def Report(root: string, report: dict<any>): void
  var findings = get(report, 'findings', [])

  var qf = findings->mapnew((_, f) => ({
    filename: $'{root}/{f.file}',
    lnum: f.line,
    col: f.col,
    text: $'[{f.class}] {f.kind} {f.name}',
  }))

  setqflist(qf, 'r')

  # A file the scan could not read is said once, because a symbol that
  # only that file uses then looks unreferenced.
  for skip in get(report, 'skipped', [])
    log.Warn(printf(MSG_SKIPPED, skip.file, skip.why))
  endfor

  # A line that reads a whole scope turns the finding off for that
  # scope. The user asked for it, so an empty list must say why.
  # REFERENCE: https://github.com/Galvarcus/GhostCode/issues/55
  for note in get(report, 'notes', [])
    log.Warn(printf(MSG_NOTE, note.file, note.line, note.scope))
  endfor

  var sum = get(report, 'summary', {})

  log.Info(printf(
    MSG_SUMMARY,
    get(sum, 'symbols', 0),
    get(sum, 'ghost', 0),
  ))

  if !empty(qf)
    copen
  endif
enddef
