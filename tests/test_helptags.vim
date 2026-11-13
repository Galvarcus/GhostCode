vim9script

##############################################################################
# Plugin_Name: Ghostcode
# tests/test_helptags.vim: the tags that :helptags finds in the help file.
# The help file is built from the readme, and the build gives a tag to each
# heading alone, so a filter adds the tag of the command and of each
# variable. These tests build the help file as the Vimdoc workflow does,
# into a directory of their own, and read the tags that Vim makes from it.
# REFERENCE: https://github.com/Galvarcus/GhostCode/issues/76
# License: GNU GPL 3.0
##############################################################################

import './skip.vim' as S

const PANDOC: string = 'pandoc'
const WRITER: string = 'vimdoc'
const DEFAULTS: string = 'doc/vimdoc.yaml'
const README: string = 'README.md'
const HELP: string = 'ghostcode.txt'
const CMD: string = ':GhostCode'
# A row of the table of variables in the readme, with the name kept.
const VAR_ROW: string = '^| `\(g:ghostcode_\w\+\)` |'

# The tags of one build, which every test reads. A build takes a
# process, so it runs once.
var built: bool = false
var tags: list<string> = []
var fault: string = ''

# FUNCTION: The reason the help file cannot be built here, or an empty
# string. The pandoc of a distribution can be older than the writer.
def Missing(): string
  if executable(PANDOC) != 1
    return $'{PANDOC} is not installed'
  endif

  if index(systemlist($'{PANDOC} --list-output-formats'), WRITER) < 0
    return $'this {PANDOC} has no {WRITER} writer'
  endif

  return ''
enddef

# FUNCTION: Build the help file and let Vim make the tags, once. A
# fault of the build or of :helptags, such as a tag that stands twice,
# is kept for the tests to report.
def Build(): void
  if built
    return
  endif

  built = true
  var dir = tempname()
  mkdir(dir, 'p')
  var out = system($'{PANDOC} --defaults={DEFAULTS} --output={shellescape(dir .. '/' .. HELP)}')

  if v:shell_error != 0
    fault = $'{PANDOC} failed: {out}'
    return
  endif

  try
    execute $'helptags {fnameescape(dir)}'
  catch
    fault = v:exception
    return
  endtry

  tags = readfile(dir .. '/tags')->mapnew((_, l) => split(l, "\t")[0])
enddef

# FUNCTION: Whether a test can run, with the skip recorded where it
# cannot.
def Ready(name: string): bool
  var why = Missing()

  if !empty(why)
    S.Skip(name, why)
    return false
  endif

  Build()
  return true
enddef

def Test_the_help_file_builds_and_no_tag_stands_twice(): void
  if !Ready('the_help_file_builds_and_no_tag_stands_twice')
    return
  endif

  assert_equal('', fault)
enddef

def Test_the_command_has_a_help_tag(): void
  if !Ready('the_command_has_a_help_tag')
    return
  endif

  assert_true(index(tags, CMD) >= 0, $'no tag for {CMD}')
enddef

# FUNCTION: The names come from the readme, so that a variable added to
# the table is held to the same rule with no change here.
def Test_each_variable_of_the_plugin_has_a_help_tag(): void
  if !Ready('each_variable_of_the_plugin_has_a_help_tag')
    return
  endif

  var names = readfile(README)
    ->mapnew((_, l) => matchlist(l, VAR_ROW))
    ->filter((_, m) => !empty(m))
    ->mapnew((_, m) => m[1])

  assert_true(len(names) > 0, 'the readme names no variable of the plugin')

  for name in names
    assert_true(index(tags, name) >= 0, $'no tag for {name}')
  endfor
enddef

export def RunAll(): void
  Test_the_help_file_builds_and_no_tag_stands_twice()
  Test_the_command_has_a_help_tag()
  Test_each_variable_of_the_plugin_has_a_help_tag()
enddef
