vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_wordcount.vim: the word counts of wordcount.vim. Folders add
# up the words inside them, an open document counts its unsaved text, and
# a file is read again only when its size or time changes. A file whose
# text changes while its size and time stay shows that the count comes
# from the cache. Vim cannot set the time of a file, so python3 does.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/wordcount.vim' as WC
import './fixtures.vim' as FI

# FUNCTION: Return the fixture project, with its two scenes on disk, and
# its two chapters and scenes.
def ProjectWithScenes(): dict<any>
  var project = FI.BuildProject()
  var chapter1 = project.ChildAt(1).ChildAt(0)
  var chapter2 = project.ChildAt(1).ChildAt(1)
  FI.WriteDocContent(project, chapter1.ChildAt(0), ['One two three.', 'Four five.'])
  FI.WriteDocContent(project, chapter2.ChildAt(0), ['Six seven'])
  return {project: project, chapter1: chapter1, chapter2: chapter2,
    scene1: chapter1.ChildAt(0), scene2: chapter2.ChildAt(0)}
enddef

# FUNCTION: Set the time of the file at path to seconds since 1970, and
# return true when the system had a way to do it. Vim cannot set a file
# time itself, so this needs a program: python3, or PowerShell on a
# Windows without one.
def SetFileTime(path: string, seconds: number): bool
  if executable('python3')
    system(printf('python3 -c "import os,sys; os.utime(sys.argv[1], (%d, %d))" %s',
      seconds, seconds, shellescape(path)))
  elseif has('win32')
    system(printf('powershell -NoProfile -Command "(Get-Item -LiteralPath ''%s'').LastWriteTimeUtc'
      .. ' = [DateTimeOffset]::FromUnixTimeSeconds(%d).UtcDateTime"', path, seconds))
  endif
  return getftime(path) == seconds
enddef

def Test_folders_add_up_the_words_inside_them(): void
  WC.ClearCache()
  var fx = ProjectWithScenes()
  var manuscript = fx.project.ChildAt(1)
  var totals = WC.Totals([manuscript], fx.project.BinderRoot())
  assert_equal(5, totals[fx.scene1.id])
  assert_equal(5, totals[fx.chapter1.id])
  assert_equal(2, totals[fx.chapter2.id])
  assert_equal(7, totals[manuscript.id])
  FI.CleanupProjectFiles(fx.project)
enddef

def Test_a_missing_file_has_no_words(): void
  WC.ClearCache()
  var fx = ProjectWithScenes()
  delete(fx.scene2.AbsPath(fx.project.BinderRoot()))
  var totals = WC.Totals([fx.chapter2], fx.project.BinderRoot())
  assert_equal(0, totals[fx.chapter2.id])
  FI.CleanupProjectFiles(fx.project)
enddef

def Test_an_open_document_counts_its_unsaved_text(): void
  WC.ClearCache()
  var fx = ProjectWithScenes()
  var path: string = fx.scene2.AbsPath(fx.project.BinderRoot())
  execute 'silent edit ' .. fnameescape(path)
  setline(1, ['Six seven eight nine ten'])
  assert_equal(5, WC.Totals([fx.chapter2], fx.project.BinderRoot())[fx.chapter2.id])
  bwipe!
  # Closed without saving, the file counts again.
  assert_equal(2, WC.Totals([fx.chapter2], fx.project.BinderRoot())[fx.chapter2.id])
  FI.CleanupProjectFiles(fx.project)
enddef

def Test_an_unchanged_file_is_read_once(): void
  WC.ClearCache()
  var fx = ProjectWithScenes()
  var path: string = fx.scene2.AbsPath(fx.project.BinderRoot())
  if !SetFileTime(path, 1000000000)
    echomsg 'SKIP: no way to set a file time'
    FI.CleanupProjectFiles(fx.project)
    return
  endif
  assert_equal(2, WC.Totals([fx.scene2], fx.project.BinderRoot())[fx.scene2.id])
  # Same size and time, other words: the count comes from the cache.
  writefile(['Sixxxxxxx'], path)
  SetFileTime(path, 1000000000)
  assert_equal(2, WC.Totals([fx.scene2], fx.project.BinderRoot())[fx.scene2.id])
  # A new time makes it read the file again.
  SetFileTime(path, 1000000100)
  assert_equal(1, WC.Totals([fx.scene2], fx.project.BinderRoot())[fx.scene2.id])
  FI.CleanupProjectFiles(fx.project)
enddef

export def RunAll(): void
  Test_folders_add_up_the_words_inside_them()
  Test_a_missing_file_has_no_words()
  Test_an_open_document_counts_its_unsaved_text()
  Test_an_unchanged_file_is_read_once()
enddef
