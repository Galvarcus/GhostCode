vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_path.vim: the one spelling of a path in path.vim, which keys a
# buffer, answers whether a document belongs to a scrive, and cuts a
# relative path out of an absolute one. The traps are a path that is
# relative, one that ends in a separator, a folder whose name begins with
# the name of another, a name that two spellings share wherever
# fileignorecase is on, and a separator of its own where a backslash
# separates a path.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/path.vim' as PA
import './fixtures.vim' as FI

# A folder of this run, which needs no file in it: Full asks the system
# only to resolve a link.
const DIR: string = substitute(fnamemodify(tempname(), ':p'), '\\', '/', 'g')

def Test_canon_answers_one_absolute_path(): void
  assert_equal('', PA.Canon(''))
  assert_equal(PA.Canon(getcwd() .. '/tests/fixtures.vim'), PA.Canon('tests/fixtures.vim'))
  # A trailing separator is not part of a name.
  assert_equal(PA.Canon(DIR), PA.Canon(DIR .. '/'))
enddef

def Test_same_holds_for_two_spellings_of_one_file(): void
  assert_true(PA.Same('tests/fixtures.vim', getcwd() .. '/tests/fixtures.vim'))
  assert_false(PA.Same('tests/fixtures.vim', 'tests/harness.vim'))
  # An empty path names no file, so it matches nothing, itself included.
  assert_false(PA.Same('', ''))
  assert_false(PA.Same('', 'tests/fixtures.vim'))
  # Case is the file system's question, not the platform's, so the option
  # decides and the test runs either way. Only the tail changes case, so
  # that no parent of it can be a link whose own case resolve answers for.
  if &fileignorecase
    assert_true(PA.Same($'{DIR}/One.md', $'{DIR}/ONE.MD'))
  else
    assert_false(PA.Same($'{DIR}/One.md', $'{DIR}/ONE.MD'))
  endif
  if exists('+shellslash')
    assert_true(PA.Same(DIR .. '/One.md', substitute(DIR .. '/One.md', '/', '\', 'g')))
  endif
enddef

def Test_canon_unresolved_tells_a_link_from_what_it_points_at(): void
  var real: string = FI.TempPath()
  mkdir(real, 'p')
  var link: string = $'{real}-link'
  if !FI.MakeLink(real, link)
    echomsg 'SKIP: the system made no symbolic link'
    delete(real, 'rf')
    return
  endif
  assert_equal(PA.Canon(real), PA.Canon(link))
  assert_notequal(PA.CanonUnresolved(link), PA.CanonUnresolved(real))
  assert_equal(PA.Canon(real), PA.CanonUnresolved(real))
  # The spelling is settled either way: no trailing slash, and the case
  # folded where Vim says the file system folds it.
  assert_equal(PA.CanonUnresolved(link), PA.CanonUnresolved($'{link}/'))
  if &fileignorecase
    assert_equal(PA.CanonUnresolved(link), PA.CanonUnresolved(toupper(link)))
  endif
  delete(link, 'rf')
  delete(real, 'rf')
enddef

def Test_same_sees_through_a_symbolic_link(): void
  var real: string = tempname()
  mkdir(real, 'p')
  var link: string = $'{real}-link'
  if !FI.MakeLink(real, link)
    echomsg 'SKIP: the system made no symbolic link'
    delete(real, 'rf')
    return
  endif
  assert_true(PA.Same(real, link))
  assert_true(PA.Same($'{real}/scene.md', $'{link}/scene.md'))
  delete(link, 'rf')
  delete(real, 'rf')
enddef

def Test_under_takes_the_root_itself_and_what_lies_in_it(): void
  assert_true(PA.Under($'{DIR}/binder', $'{DIR}/binder'))
  assert_true(PA.Under($'{DIR}/binder', $'{DIR}/binder/chapter-1/scene-01.md'))
  # The trap of a prefix: a sibling whose name begins with the name of the
  # root is not in it.
  assert_false(PA.Under($'{DIR}/binder', $'{DIR}/binderly/scene.md'))
  assert_false(PA.Under($'{DIR}/binder', $'{DIR}/other/scene.md'))
  assert_false(PA.Under('', $'{DIR}/binder/scene.md'))
  assert_false(PA.Under($'{DIR}/binder', ''))
  if &fileignorecase
    assert_true(PA.Under($'{DIR}/binder', $'{DIR}/BINDER/scene.md'))
  endif
enddef

def Test_rel_cuts_the_part_below_the_root(): void
  assert_equal('chapter-1/scene-01.md', PA.Rel($'{DIR}/binder', $'{DIR}/binder/chapter-1/scene-01.md'))
  # The case of the path is the case of the answer, because a scrive keeps
  # what Rel gives it.
  assert_equal('Chapter-1/Scene-01.md', PA.Rel($'{DIR}/binder', $'{DIR}/binder/Chapter-1/Scene-01.md'))
  # Nothing below the root, and nothing in it: both are no relative path.
  assert_equal('', PA.Rel($'{DIR}/binder', $'{DIR}/binder'))
  assert_equal('', PA.Rel($'{DIR}/binder', $'{DIR}/binderly/scene.md'))
  assert_equal('', PA.Rel($'{DIR}/binder', $'{DIR}/other/scene.md'))
  assert_equal('', PA.Rel('', $'{DIR}/binder/scene.md'))
  # The root reaches Rel in whatever case its own source spelled it.
  if &fileignorecase
    assert_equal('Chapter-1/Scene-01.md', PA.Rel($'{DIR}/BINDER', $'{DIR}/binder/Chapter-1/Scene-01.md'))
  endif
enddef

# Folded answers what this file system does with case, which is what a
# path comparison asks. A test of the search for a free name asks the
# other question, see test_layout.vim.
def Test_folded_answers_for_this_file_system(): void
  assert_equal(&fileignorecase ? 'über.md' : 'Über.md', PA.Folded('Über.md'))
enddef

export def RunAll(): void
  Test_folded_answers_for_this_file_system()
  Test_canon_answers_one_absolute_path()
  Test_same_holds_for_two_spellings_of_one_file()
  Test_canon_unresolved_tells_a_link_from_what_it_points_at()
  Test_same_sees_through_a_symbolic_link()
  Test_under_takes_the_root_itself_and_what_lies_in_it()
  Test_rel_cuts_the_part_below_the_root()
enddef
