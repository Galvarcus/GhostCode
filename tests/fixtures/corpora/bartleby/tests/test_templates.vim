vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_templates.vim: the starter trees of templates.vim. Each scrive
# type gets its folders, with their roles, in order, and documents with
# the extension of the type at paths that do not repeat. Materialize makes
# the missing files and never writes over a file that has text.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/templates.vim' as TE
import 'bartleby/variables/constants.vim' as CO
import './fixtures.vim' as FI

# FUNCTION: Return the documents inside items, at any depth.
def Documents(items: list<any>): list<any>
  var found: list<any> = []
  for item in items
    found += item.IsDoc() ? [item] : Documents(item.children)
  endfor
  return found
enddef

def Roles(items: list<any>): list<string>
  return items->mapnew((_, item) => item.structureRole)
enddef

def Test_each_type_gets_its_folders_in_order(): void
  assert_equal([CO.ROLE_FRONT_MATTER, CO.ROLE_MANUSCRIPT, CO.ROLE_BACK_MATTER, CO.ROLE_CHARS,
    CO.ROLE_RESEARCH], Roles(TE.DefaultTree(CO.TYPE_NOVEL, '.md')))
  var parts = TE.DefaultTree(CO.TYPE_NOVEL_PARTS, '.md')
  assert_equal(Roles(TE.DefaultTree(CO.TYPE_NOVEL, '.md')), Roles(parts))
  assert_equal([CO.ROLE_PART, CO.ROLE_PART], Roles(parts[1].children))
  assert_equal([CO.ROLE_FRONT_MATTER, CO.ROLE_MANUSCRIPT, CO.ROLE_BACK_MATTER, CO.ROLE_CHARS,
    CO.ROLE_RESEARCH], Roles(TE.DefaultTree(CO.TYPE_SHORT_STORY, '.md')))
  assert_equal([CO.ROLE_FRONT_MATTER, CO.ROLE_MANUSCRIPT, CO.ROLE_CHARS, CO.ROLE_RESEARCH],
    Roles(TE.DefaultTree(CO.TYPE_SCREENPLAY, '.fountain')))
enddef

# FUNCTION: A short story has one document, Draft, directly in Manuscript, and
# every other folder starts empty.
def Test_a_short_story_starts_with_one_draft_and_empty_folders(): void
  var tree = TE.DefaultTree(CO.TYPE_SHORT_STORY, '.md')
  assert_equal(1, len(tree[1].children))
  if len(tree[1].children) == 1
    assert_true(tree[1].children[0].IsDoc())
  endif
  for index in [0, 2, 3, 4]
    assert_equal([], tree[index].children, tree[index].structureRole)
  endfor
enddef

def Test_documents_use_the_extension_and_unique_paths(): void
  for [projectType, ext] in [[CO.TYPE_NOVEL, '.md'], [CO.TYPE_NOVEL_PARTS, '.md'],
      [CO.TYPE_SHORT_STORY, '.md'], [CO.TYPE_SCREENPLAY, '.fountain']]
    var paths: list<string> = Documents(TE.DefaultTree(projectType, ext))->mapnew((_, d) => d.relPath)
    assert_false(empty(paths), projectType)
    assert_equal([], paths->copy()->filter((_, p) => p !~# '\V' .. ext .. '\$'), projectType)
    assert_equal(len(paths), len(uniq(sort(copy(paths)))), projectType)
  endfor
enddef

def Test_an_unknown_type_gets_nothing(): void
  assert_equal([], TE.DefaultTree('no such type', '.md'))
enddef

def Test_materialize_makes_missing_files_and_keeps_written_ones(): void
  var root: string = FI.TempPath()
  var items = TE.DefaultTree(CO.TYPE_NOVEL, '.md')
  var docs = Documents(items)
  var kept: string = docs[0].AbsPath(root)
  mkdir(fnamemodify(kept, ':h'), 'p')
  writefile(['Words already written.'], kept)
  TE.Materialize(items, root)
  for doc in docs
    assert_true(filereadable(doc.AbsPath(root)), doc.relPath)
  endfor
  assert_equal(['Words already written.'], readfile(kept))
  delete(root, 'rf')
enddef

export def RunAll(): void
  Test_each_type_gets_its_folders_in_order()
  Test_a_short_story_starts_with_one_draft_and_empty_folders()
  Test_documents_use_the_extension_and_unique_paths()
  Test_an_unknown_type_gets_nothing()
  Test_materialize_makes_missing_files_and_keeps_written_ones()
enddef
