vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_profile.vim: the name parts of ProjectInfo in profile.vim.
# A profile saved with one name is split into parts once, the full name
# joins the parts that are not empty, and the author falls back to it.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/profile.vim' as PR

def Test_old_single_name_is_split(): void
  var info = PR.ProjInfo.FromDict({name: 'Mary Ann Evans'})
  assert_equal(['Mary', 'Ann', 'Evans'], [info.firstname, info.middlename, info.surname])
  info = PR.ProjInfo.FromDict({name: 'Cher'})
  assert_equal(['Cher', '', ''], [info.firstname, info.middlename, info.surname])
enddef

def Test_name_parts_win_over_an_old_name(): void
  var info = PR.ProjInfo.FromDict({name: 'Old Name', firstname: 'New', surname: 'Parts'})
  assert_equal('New Parts', info.FullName())
enddef

def Test_full_name_joins_the_parts_that_are_set(): void
  var info = PR.ProjInfo.FromDict({prefix: 'Dr.', firstname: 'Jane', surname: 'Doe', suffix: 'Jr.'})
  assert_equal('Dr. Jane Doe Jr.', info.FullName())
  assert_equal('Dr. Jane Doe Jr.', info.EffectiveAuthor())
  info = PR.ProjInfo.FromDict({firstname: 'Jane', surname: 'Doe', authorname: 'J. D. Penn'})
  assert_equal('J. D. Penn', info.EffectiveAuthor())
enddef

def Test_saved_profile_has_parts_not_the_old_name(): void
  var saved = PR.ProjInfo.FromDict({name: 'Mary Ann Evans'}).ToDict()
  assert_false(has_key(saved, 'name'))
  assert_equal('Evans', saved.surname)
enddef

export def RunAll(): void
  Test_old_single_name_is_split()
  Test_name_parts_win_over_an_old_name()
  Test_full_name_joins_the_parts_that_are_set()
  Test_saved_profile_has_parts_not_the_old_name()
enddef
