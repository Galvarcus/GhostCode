vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_restore.vim: Restore of restore.vim puts back a session: the
# document that was open, at its cursor, the collapsed folders, and the
# Binder open or closed. A document deleted since leaves the rest of the
# session in place.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/restore.vim' as R
import autoload 'bartleby/binder.vim' as B
import autoload 'bartleby/path.vim' as PA
import autoload 'bartleby/persist.vim' as PE
import autoload 'bartleby/session.vim' as SS
import autoload 'bartleby/state.vim' as ST
import './fixtures.vim' as FI
import 'bartleby/variables/constants.vim' as CO

# FUNCTION: Return the fixture project, current, with a scene on disk and
# a saved session.
def ProjectWithSession(session: dict<any>): dict<any>
  SS.ForgetKnownStates()
  var project = FI.BuildProject()
  var scene = project.ChildAt(1).ChildAt(0).ChildAt(0)
  FI.WriteDocContent(project, scene, ['One.', 'Two words.', 'Three more words.'])
  PE.WriteJson(project.scriveDir .. '/session.json', session)
  ST.Set(project)
  return {project: project, scene: scene, chapter2: project.ChildAt(1).ChildAt(1)}
enddef

def Close(fx: dict<any>): void
  execute 'silent! bwipe! ' .. CO.BINDER_BUF
  silent! only
  silent! :%bwipe!
  ST.Set(null_object)
  SS.ForgetKnownStates()
  FI.CleanupProjectFiles(fx.project)
enddef

def Test_restore_opens_the_document_at_its_cursor(): void
  var fx = ProjectWithSession({activeDocRelPath: 'chapter-1/scene-01.md',
    cursorLine: 3, cursorCol: 7, binderOpen: true, collapsedIds: []})
  R.Restore(fx.project)
  assert_equal(PA.Canon(fx.scene.AbsPath(fx.project.BinderRoot())), PA.Canon(expand('%:p')))
  assert_equal([3, 7], [line('.'), col('.')])
  assert_true(B.IsOpen())
  Close(fx)
enddef

def Test_restore_applies_the_collapsed_folders_and_a_closed_binder(): void
  var fx = ProjectWithSession({})
  PE.WriteJson(fx.project.scriveDir .. '/session.json', {activeDocRelPath: '',
    binderOpen: false, collapsedIds: [fx.chapter2.id]})
  R.Restore(fx.project)
  assert_false(B.IsOpen())
  assert_equal({[fx.chapter2.id]: true}, getbufvar(CO.BINDER_BUF, 'bartleby_collapsed', {}))
  Close(fx)
enddef

def Test_a_deleted_document_leaves_the_rest_of_the_session(): void
  var fx = ProjectWithSession({activeDocRelPath: 'gone.md', cursorLine: 2, cursorCol: 1,
    binderOpen: true, collapsedIds: []})
  R.Restore(fx.project)
  assert_notequal('gone.md', expand('%:t'))
  assert_true(B.IsOpen())
  Close(fx)
enddef

export def RunAll(): void
  Test_restore_opens_the_document_at_its_cursor()
  Test_restore_applies_the_collapsed_folders_and_a_closed_binder()
  Test_a_deleted_document_leaves_the_rest_of_the_session()
enddef
