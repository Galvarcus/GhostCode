vim9script

##############################################################################
# Plugin_Name: Logger
# Tests logfile.vim: the session file name, appends, the retention of old
# files, a change of folder, and the error for a folder Vim cannot make.
# License: GNU GPL 3.0
##############################################################################

import 'Logger/logfile.vim' as L

const SESSION_NAME: string = '^foo_\d\{8}_\d\{6}\.log$'

def Test_creates_folder_and_appends(): void
  var dir: string = $'{tempname()}/sub'
  var file = L.LogFile.new('foo')
  file.Write(['one'], dir, 10)
  file.Write(['two', 'three'], dir, 10)
  var names: list<string> = readdir(dir)
  assert_equal(1, len(names))
  assert_match(SESSION_NAME, names[0])
  assert_equal(['one', 'two', 'three'], readfile($'{dir}/{names[0]}'))
  delete(fnamemodify(dir, ':h'), 'rf')
enddef

def Test_keeps_only_retention_old_files(): void
  var dir: string = tempname()
  mkdir(dir, 'p')
  for d in range(1, 5)
    writefile(['old'], $'{dir}/foo_2020010{d}_000000.log')
  endfor
  writefile(['other plugin'], $'{dir}/foo_bar_20200101_000000.log')
  writefile(['not a log'], $'{dir}/notes.txt')
  var file = L.LogFile.new('foo')
  file.Write(['new'], dir, 2)
  var names: list<string> = readdir(dir)
  assert_equal(5, len(names))
  assert_equal(-1, index(names, 'foo_20200101_000000.log'))
  assert_equal(-1, index(names, 'foo_20200103_000000.log'))
  assert_notequal(-1, index(names, 'foo_20200104_000000.log'))
  assert_notequal(-1, index(names, 'foo_20200105_000000.log'))
  assert_notequal(-1, index(names, 'foo_bar_20200101_000000.log'))
  assert_notequal(-1, index(names, 'notes.txt'))
  assert_equal(['new'], readfile(file.path))
  delete(dir, 'rf')
enddef

def Test_retention_zero_keeps_all(): void
  var dir: string = tempname()
  mkdir(dir, 'p')
  for d in range(1, 3)
    writefile(['old'], $'{dir}/foo_2020010{d}_000000.log')
  endfor
  L.LogFile.new('foo').Write(['new'], dir, 0)
  assert_equal(4, len(readdir(dir)))
  delete(dir, 'rf')
enddef

def Test_new_folder_starts_new_file(): void
  var first: string = tempname()
  var second: string = tempname()
  var file = L.LogFile.new('foo')
  file.Write(['a'], first, 10)
  file.Write(['b'], second, 10)
  assert_match($'^{second}', file.path)
  assert_equal(1, len(readdir(first)))
  assert_equal(1, len(readdir(second)))
  delete(first, 'rf')
  delete(second, 'rf')
enddef

def Test_throws_when_folder_is_a_file(): void
  var blocker: string = tempname()
  writefile(['file'], blocker)
  var failed: bool = false
  try
    L.LogFile.new('foo').Write(['a'], $'{blocker}/logs', 10)
  catch
    failed = true
  endtry
  assert_true(failed)
  delete(blocker)
enddef

export def RunAll(): void
  Test_creates_folder_and_appends()
  Test_keeps_only_retention_old_files()
  Test_retention_zero_keeps_all()
  Test_new_folder_starts_new_file()
  Test_throws_when_folder_is_a_file()
enddef
