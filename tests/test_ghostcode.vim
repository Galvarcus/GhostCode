vim9script

##############################################################################
# Plugin_Name: Ghostcode
# tests/test_ghostcode.vim: what Ghostcode reports for small projects that
# each test writes into a temporary folder. Covers the setting that decides
# whether an export is public API, the rule that an ambiguous name counts
# every candidate as used, and the class-qualified call, as in M.Menu.new().
# License: GNU GPL 3.0
##############################################################################

import autoload 'ghostcode.vim' as GC

# FUNCTION: Write the files, a dict of path to lines, under a new folder, and
# return the folder.
def Project(files: dict<list<string>>): string
  var root = tempname()
  for [path, lines] in items(files)
    var full = $'{root}/{path}'
    mkdir(fnamemodify(full, ':h'), 'p')
    writefile(lines, full)
  endfor
  return root
enddef

# FUNCTION: Run Ghostcode on the files with the setting as given, and return
# what it reports as `kind name`, sorted.
def Ghosts(files: dict<list<string>>, exportsAreApi: bool = true): list<string>
  var root = Project(files)
  var saved = g:ghostcode_exports_are_api
  g:ghostcode_exports_are_api = exportsAreApi
  try
    GC.Run(root)
  finally
    g:ghostcode_exports_are_api = saved
  endtry
  var found = getqflist()
    ->mapnew((_, item) => substitute(item.text, '^\[ghost\] ', '', ''))
    ->sort()
  silent! cclose
  delete(root, 'rf')
  return found
enddef

# A plugin with an exported class and two exported functions. The plugin
# script uses one function and one method. The other function and method are
# exported and used by nothing.
def Library(): dict<list<string>>
  return {
    'autoload/lib.vim': [
      'vim9script',
      'export class Thing',
      '  def Used()',
      '  enddef',
      '  def Unused()',
      '  enddef',
      'endclass',
      'export def Helper()',
      'enddef',
      'export def Orphan()',
      'enddef',
    ],
    'plugin/p.vim': [
      'vim9script',
      'import autoload "lib.vim" as L',
      'L.Helper()',
      'var t = L.Thing.new()',
      't.Used()',
    ],
  }
enddef

def Test_the_setting_defaults_to_exports_being_api(): void
  assert_equal(true, g:ghostcode_exports_are_api)
enddef

# FUNCTION: A :let on the command line gives a number, as the CI of a
# project does. 0 turns the mode on and 1 leaves it off.
def Test_the_setting_accepts_a_number(): void
  var saved = g:ghostcode_exports_are_api
  g:ghostcode_exports_are_api = 0
  try
    var root = Project(Library())
    GC.Run(root)
    var strict = getqflist()->mapnew((_, item) => substitute(item.text, '^\[ghost\] ', '', ''))->sort()
    g:ghostcode_exports_are_api = 1
    GC.Run(root)
    var api = getqflist()->len()
    silent! cclose
    delete(root, 'rf')
    assert_equal(['function Orphan', 'method Unused'], strict)
    assert_equal(0, api)
  finally
    g:ghostcode_exports_are_api = saved
  endtry
enddef

def Test_an_export_is_api_by_default(): void
  assert_equal([], Ghosts(Library()))
enddef

def Test_strict_mode_reports_an_export_that_nothing_uses(): void
  assert_equal(['function Orphan', 'method Unused'], Ghosts(Library(), false))
enddef

def Test_a_symbol_nothing_reaches_is_reported_in_both_modes(): void
  var files = Library()
  files['autoload/lib.vim'] += ['def Dead()', 'enddef']
  assert_equal(['function Dead'], Ghosts(files))
  assert_equal(['function Dead', 'function Orphan', 'method Unused'], Ghosts(files, false))
enddef

# FUNCTION: Two classes have a Close method, and the call goes through a
# parameter with no type. The call might reach either, so both count as used.
# The method that is unique by name is still reported.
def Test_every_candidate_of_an_ambiguous_name_counts_as_used(): void
  var files = {
    'autoload/a.vim': [
      'vim9script',
      'export class A',
      '  def Close()',
      '  enddef',
      'endclass',
      'export class B',
      '  def Close()',
      '  enddef',
      '  def Other()',
      '  enddef',
      'endclass',
    ],
    'plugin/p.vim': [
      'vim9script',
      'import autoload "a.vim" as X',
      'def Run(thing: any)',
      '  thing.Close()',
      'enddef',
      'Run(X.A.new())',
      'Run(X.B.new())',
    ],
  }
  assert_equal(['method Other'], Ghosts(files, false))
enddef

# FUNCTION: Two files define Helper, and a string names it, as call() does.
# Nothing says which file is meant, so both count as used.
def Test_a_bare_name_that_two_files_define_counts_for_both(): void
  var files = {
    'autoload/a.vim': ['vim9script', 'export def Helper()', 'enddef'],
    'autoload/b.vim': ['vim9script', 'export def Helper()', 'enddef'],
    'plugin/p.vim': [
      'vim9script',
      'import autoload "a.vim" as A',
      'import autoload "b.vim" as B',
      'call("Helper", [])',
    ],
  }
  assert_equal([], Ghosts(files, false))
enddef

# FUNCTION: M.Menu.new() shows the scanner only Menu.new. Both classes have a
# constructor, so a match by member name alone is ambiguous and would count
# both. Finding the class by name counts only the right one, and the
# constructor of the class that nothing builds is reported.
def Test_a_class_qualified_call_reaches_only_its_own_member(): void
  var files = {
    'autoload/m.vim': [
      'vim9script',
      'export class Menu',
      '  def new(this.label: string)',
      '  enddef',
      'endclass',
      'export class Other',
      '  def new()',
      '  enddef',
      'endclass',
    ],
    'plugin/p.vim': [
      'vim9script',
      'import autoload "m.vim" as M',
      'M.Menu.new("x")',
    ],
  }
  assert_equal(['class Other', 'method new'], Ghosts(files, false))
enddef

# FUNCTION: A class with no new method has the default constructor, which is
# no symbol. Building it must not credit the constructor of another class.
def Test_a_default_constructor_credits_nothing(): void
  var files = {
    'autoload/m.vim': [
      'vim9script',
      'export class Plain',
      'endclass',
      'export class Other',
      '  def new()',
      '  enddef',
      'endclass',
    ],
    'plugin/p.vim': [
      'vim9script',
      'import autoload "m.vim" as M',
      'M.Plain.new()',
    ],
  }
  assert_equal(['class Other', 'method new'], Ghosts(files, false))
enddef

def Test_a_field_read_through_an_untyped_receiver_counts(): void
  var files = {
    'autoload/f.vim': [
      'vim9script',
      'export class Item',
      '  public var label: string',
      'endclass',
      'export class Entry',
      '  public var label: string',
      'endclass',
    ],
    'plugin/p.vim': [
      'vim9script',
      'import autoload "f.vim" as F',
      'def Show(thing: any): string',
      '  return thing.label',
      'enddef',
      'Show(F.Item.new())',
      'Show(F.Entry.new())',
    ],
  }
  assert_equal([], Ghosts(files, false))
enddef

export def RunAll(): void
  Test_the_setting_defaults_to_exports_being_api()
  Test_the_setting_accepts_a_number()
  Test_an_export_is_api_by_default()
  Test_strict_mode_reports_an_export_that_nothing_uses()
  Test_a_symbol_nothing_reaches_is_reported_in_both_modes()
  Test_every_candidate_of_an_ambiguous_name_counts_as_used()
  Test_a_bare_name_that_two_files_define_counts_for_both()
  Test_a_class_qualified_call_reaches_only_its_own_member()
  Test_a_default_constructor_credits_nothing()
  Test_a_field_read_through_an_untyped_receiver_counts()
enddef
