vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_persist.vim: the safe writes of persist.vim. A write fills a
# temporary file that then replaces the file, keeps a backup when asked,
# and leaves the file as it was when a step fails. A directory in the way
# of the temporary file makes a write fail, even for root, who can write
# where permissions forbid it.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/persist.vim' as PE
import './fixtures.vim' as FI

# FUNCTION: Return a path for a JSON file in a new temporary directory.
def NewPath(): string
  var dir: string = tempname()
  mkdir(dir, 'p')
  return dir .. '/data.json'
enddef

# FUNCTION: Return a new temporary folder and a folder two levels inside
# it, both made. The folder comes from the fixtures, which answer with the
# spelling that Vim uses elsewhere.
def NewTree(): list<string>
  var root: string = FI.TempPath()
  var deep: string = $'{root}/chapter-1/scenes'
  mkdir(deep, 'p')
  return [root, deep]
enddef

def Test_an_empty_folder_goes_when_the_root_carries_a_trailing_slash(): void
  var [root, deep] = NewTree()
  PE.RemoveEmptyDirectories(deep, root .. '/')
  assert_false(isdirectory(deep), 'the empty folder stayed')
  assert_false(isdirectory(fnamemodify(deep, ':h')), 'the folder above it stayed')
  assert_true(isdirectory(root), 'the root went')
  delete(root, 'rf')
enddef

def Test_an_empty_folder_goes_when_the_root_is_spelled_in_another_case(): void
  var [root, deep] = NewTree()
  PE.RemoveEmptyDirectories(deep, toupper(root))
  if &fileignorecase
    assert_false(isdirectory(deep), 'the empty folder stayed')
    assert_true(isdirectory(root), 'the root went')
  else
    # Another case names another folder where Vim says nothing folds, so
    # the walk must not begin at all.
    assert_true(isdirectory(deep), 'a folder outside the root went')
  endif
  delete(root, 'rf')
enddef

def Test_a_write_replaces_the_file_and_leaves_no_temporary_file(): void
  var path: string = NewPath()
  assert_true(PE.WriteJson(path, {version: 1}))
  assert_true(PE.WriteJson(path, {version: 2}))
  assert_equal({version: 2}, PE.ReadJson(path))
  assert_equal(['data.json'], readdir(fnamemodify(path, ':h')))
  delete(fnamemodify(path, ':h'), 'rf')
enddef

def Test_a_backup_keeps_the_version_before_the_write(): void
  var path: string = NewPath()
  PE.WriteJson(path, {version: 1}, true)
  assert_false(filereadable(path .. PE.BACKUP_SUFFIX))
  PE.WriteJson(path, {version: 2}, true)
  assert_equal({version: 1}, PE.ReadJson(path .. PE.BACKUP_SUFFIX))
  assert_equal({version: 2}, PE.ReadJson(path))
  delete(fnamemodify(path, ':h'), 'rf')
enddef

def Test_no_backup_unless_asked(): void
  var path: string = NewPath()
  PE.WriteJson(path, {version: 1})
  PE.WriteJson(path, {version: 2})
  assert_false(filereadable(path .. PE.BACKUP_SUFFIX))
  delete(fnamemodify(path, ':h'), 'rf')
enddef

def Test_a_failed_write_leaves_the_file_as_it_was(): void
  var path: string = NewPath()
  PE.WriteJson(path, {version: 1})
  mkdir(path .. '.tmp')
  assert_false(PE.WriteJson(path, {version: 2}, true))
  assert_equal({version: 1}, PE.ReadJson(path))
  assert_false(filereadable(path .. PE.BACKUP_SUFFIX))
  delete(fnamemodify(path, ':h'), 'rf')
enddef

def Test_a_missing_folder_is_made(): void
  var path: string = tempname() .. '/deeper/data.json'
  assert_true(PE.WriteJson(path, {version: 1}))
  assert_equal({version: 1}, PE.ReadJson(path))
  delete(fnamemodify(path, ':h:h'), 'rf')
enddef

export def RunAll(): void
  Test_an_empty_folder_goes_when_the_root_carries_a_trailing_slash()
  Test_an_empty_folder_goes_when_the_root_is_spelled_in_another_case()
  Test_a_write_replaces_the_file_and_leaves_no_temporary_file()
  Test_a_backup_keeps_the_version_before_the_write()
  Test_no_backup_unless_asked()
  Test_a_failed_write_leaves_the_file_as_it_was()
  Test_a_missing_folder_is_made()
enddef
