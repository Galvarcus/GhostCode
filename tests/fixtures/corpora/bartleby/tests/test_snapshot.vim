vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_snapshot.vim: the Restore of snapshot.vim, which reloads the
# document in its window so the writer sees the restored text at once. The
# trap is the window it picks. A path handed to bufnr names the buffer of
# that file when one holds it, and otherwise is read as a pattern, which
# can answer with any buffer whose name merely contains the path. Reloading
# that one would throw away text the writer had not saved.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/43
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/snapshot.vim' as SN
import './fixtures.vim' as FI

# FUNCTION: Return the fixture project with the file of its first scene on
# disk, and that scene.
def ProjectAndScene(): list<any>
  var project = FI.BuildProject()
  var scene = project.ChildAt(1).ChildAt(0).ChildAt(0)
  FI.WriteDocContent(project, scene, ['The text as it was.'])
  return [project, scene]
enddef

def Test_a_snapshot_is_found_while_wildignore_names_its_extension(): void
  var [project, scene] = ProjectAndScene()
  SN.Take(project, scene, 'first')
  var saved: string = &wildignore
  # A writer who also edits code may well ignore JSON, and a snapshot of a
  # document is a JSON file.
  set wildignore+=*.json
  try
    assert_equal(1, len(SN.List(project, scene)))
  finally
    &wildignore = saved
  endtry
  FI.CleanupProjectFiles(project)
enddef

def Test_restore_reloads_the_document_in_its_window(): void
  var [project, scene] = ProjectAndScene()
  var path: string = scene.AbsPath(project.BinderRoot())
  SN.Take(project, scene, '')
  var snap = SN.List(project, scene)[0]
  # The buffer opens on the later text, so only a reload can show the
  # restored text.
  writefile(['The text as it became.'], path)
  execute 'edit ' .. fnameescape(path)
  var buf: number = bufnr('%')
  assert_equal(['The text as it became.'], getbufline(buf, 1, '$'))
  SN.Restore(project, scene, snap)
  assert_equal(snap.lines, getbufline(buf, 1, '$'))
  silent! execute 'bwipe! ' .. buf
  FI.CleanupProjectFiles(project)
enddef

def Test_restore_leaves_the_window_of_another_buffer_alone(): void
  var [project, scene] = ProjectAndScene()
  var path: string = scene.AbsPath(project.BinderRoot())
  SN.Take(project, scene, '')
  var snap = SN.List(project, scene)[0]
  writefile(['The text as it became.'], path)
  if bufexists(path)
    silent! execute 'bwipe! ' .. bufnr(path)
  endif
  # No buffer holds the document, and this one's name contains its path, so
  # it is what bufnr answers with once it falls back to a pattern.
  var decoy: string = path .. '-decoy.md'
  writefile(['Saved.'], decoy)
  execute 'edit ' .. fnameescape(decoy)
  var decoyBuf: number = bufnr('%')
  setline(1, 'Not saved yet.')
  SN.Restore(project, scene, snap)
  assert_equal(['Not saved yet.'], getbufline(decoyBuf, 1, '$'))
  assert_true(getbufvar(decoyBuf, '&modified'))
  # The file itself was still restored.
  assert_equal(snap.lines, readfile(path))
  silent! execute 'bwipe! ' .. decoyBuf
  delete(decoy)
  FI.CleanupProjectFiles(project)
enddef

export def RunAll(): void
  Test_a_snapshot_is_found_while_wildignore_names_its_extension()
  Test_restore_reloads_the_document_in_its_window()
  Test_restore_leaves_the_window_of_another_buffer_alone()
enddef
