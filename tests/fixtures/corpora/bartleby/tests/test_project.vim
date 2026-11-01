vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_project.vim: FindItemByPath of project.vim, which answers which
# document a buffer holds. Everything that asks whether the writer is in a
# document of the scrive goes through it, by way of DocHere in
# scrivenings.vim: the Inspector, Spotlight, and the Scrivening itself all
# refuse to open when it answers nothing. So it must find the file, not a
# spelling of its path.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/50
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/project.vim' as PO
import './fixtures.vim' as FI

def Test_a_document_is_found_by_its_own_path(): void
  var project = FI.BuildProject()
  var scene = project.ChildAt(1).ChildAt(0).ChildAt(0)
  var found = project.FindItemByPath(scene.AbsPath(project.BinderRoot()))
  assert_false(found is null_object, 'the document was not found by its own path')
  if found isnot null_object
    assert_equal(scene.id, found.id)
  endif
  assert_true(project.FindItemByPath($'{project.BinderRoot()}/nothing.md') is null_object)
  assert_true(project.FindItemByPath('') is null_object)
  # A folder is not a document, so neither is its path.
  assert_true(project.FindItemByPath(project.ChildAt(1).AbsPath(project.BinderRoot())) is null_object)
  FI.CleanupProjectFiles(project)
enddef

# FUNCTION: The fault of #50: Vim answers expand('%:p') with the separator
# of its own system and with symbolic links resolved, while AbsPath builds
# a path from what the scrive stores, so the two spell one file two ways.
def Test_a_document_is_found_by_another_spelling_of_its_path(): void
  var project = FI.BuildProject()
  var scene = project.ChildAt(1).ChildAt(0).ChildAt(0)
  # On disk first: a link to a folder that does not exist is a link that
  # getftype does not answer for, so MakeLink would report none.
  FI.WriteDocContent(project, scene, ['Text.'])
  var link: string = $'{project.BinderRoot()}-link'
  if !FI.MakeLink(project.BinderRoot(), link)
    echomsg 'SKIP: the system made no symbolic link'
    FI.CleanupProjectFiles(project)
    return
  endif
  # Asked for its id, a null_object throws, and a suite that throws writes
  # no result at all, so the answer is checked before it is read.
  var found = project.FindItemByPath($'{link}/{scene.relPath}')
  assert_false(found is null_object, 'the document was not found through the link')
  if found isnot null_object
    assert_equal(scene.id, found.id)
  endif
  delete(link, 'rf')
  FI.CleanupProjectFiles(project)
enddef

export def RunAll(): void
  Test_a_document_is_found_by_its_own_path()
  Test_a_document_is_found_by_another_spelling_of_its_path()
enddef
