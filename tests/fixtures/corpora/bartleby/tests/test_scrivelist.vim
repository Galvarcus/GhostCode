vim9script
##############################################################################
# Plugin_Name: Bartleby
# tests/test_scrivelist.vim: CandidateDirs, ReadEntry, FindScrives, and
# TypeLabel of scrivelist.vim. Builds a binder root under tempname with
# valid and invalid .bartleby folders, and removes it after each test.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/scrivelist.vim' as SL
import './fixtures.vim' as FI

def MakeScrive(root: string, folder: string, json: string): void
  var dir: string = root .. '/' .. folder .. '.bartleby'
  mkdir(dir, 'p')
  if json !=# ''
    writefile([json], dir .. '/project.json')
  endif
enddef

def BuildRoot(): string
  var root: string = FI.TempPath()
  mkdir(root, 'p')
  MakeScrive(root, 'Alpha', '{"name":"alpha novel","projectType":"novel","items":[]}')
  MakeScrive(root, 'zeta', '{"name":"Zeta Script","projectType":"screenplay","items":[]}')
  MakeScrive(root, 'NoName', '{"projectType":"novel_parts","items":[]}')
  MakeScrive(root, 'NoJson', '')
  MakeScrive(root, 'Broken', '{not json')
  MakeScrive(root, 'BadType', '{"name":"x","projectType":"poem","items":[]}')
  MakeScrive(root, 'NoItems', '{"name":"y","projectType":"novel"}')
  writefile([], root .. '/file.bartleby')
  return root
enddef

def Test_candidate_dirs_lists_only_bartleby_directories(): void
  var root: string = BuildRoot()
  # 7 folders. The plain file named file.bartleby is not a folder.
  assert_equal(7, len(SL.CandidateDirs(root)))
  delete(root, 'rf')
enddef

def Test_candidate_dirs_of_a_missing_root_is_empty(): void
  assert_equal([], SL.CandidateDirs(tempname()))
enddef

def Test_find_scrives_keeps_only_valid_projects_sorted_by_title(): void
  var root: string = BuildRoot()
  var entries = SL.FindScrives(root)
  var titles = entries->mapnew((_, e) => e.title)
  # Sorted without regard to case: alpha, NoName, Zeta.
  assert_equal(['alpha novel', 'NoName', 'Zeta Script'], titles)
  delete(root, 'rf')
enddef

def Test_find_scrives_uses_folder_name_for_opening(): void
  var root: string = BuildRoot()
  var names = SL.FindScrives(root)->mapnew((_, e) => e.name)
  assert_equal(['Alpha', 'NoName', 'zeta'], names)
  delete(root, 'rf')
enddef

def Test_read_entry_rejects_each_invalid_case(): void
  var root: string = BuildRoot()
  for folder in ['NoJson', 'Broken', 'BadType', 'NoItems']
    assert_true(SL.ReadEntry(root .. '/' .. folder .. '.bartleby') is null_object,
      folder .. ' should be rejected')
  endfor
  delete(root, 'rf')
enddef

def Test_read_entry_falls_back_to_folder_name_without_a_name(): void
  var root: string = BuildRoot()
  var entry = SL.ReadEntry(root .. '/NoName.bartleby')
  assert_equal('NoName', entry.title)
  assert_equal('novel_parts', entry.projectType)
  delete(root, 'rf')
enddef

def Test_type_label_maps_every_project_type(): void
  assert_equal('Novel', SL.TypeLabel('novel'))
  assert_equal('Novel with Parts', SL.TypeLabel('novel_parts'))
  assert_equal('Short Story', SL.TypeLabel('short_story'))
  assert_equal('Screenplay', SL.TypeLabel('screenplay'))
enddef

export def RunAll(): void
  Test_candidate_dirs_lists_only_bartleby_directories()
  Test_candidate_dirs_of_a_missing_root_is_empty()
  Test_find_scrives_keeps_only_valid_projects_sorted_by_title()
  Test_find_scrives_uses_folder_name_for_opening()
  Test_read_entry_rejects_each_invalid_case()
  Test_read_entry_falls_back_to_folder_name_without_a_name()
  Test_type_label_maps_every_project_type()
enddef
