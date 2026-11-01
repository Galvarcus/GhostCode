vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_session.vim: the captures of session.vim write session.json
# only when the state changes, and keep the fields that they do not set.
# A deleted session.json shows whether a capture wrote: one that changes
# nothing must not make it again.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/session.vim' as SS
import autoload 'bartleby/state.vim' as ST
import autoload 'bartleby/persist.vim' as PE
import './fixtures.vim' as FI

# FUNCTION: Open the first scene of the fixture project as the current
# scrive. Returns the project, the scene file, and the session file.
def OpenScene(): dict<any>
  SS.ForgetKnownStates()
  var project = FI.BuildProject()
  var scene = project.ChildAt(1).ChildAt(0).ChildAt(0)
  FI.WriteDocContent(project, scene, ['One.', 'Two.', 'Three.'])
  ST.Set(project)
  var path: string = scene.AbsPath(project.BinderRoot())
  execute 'silent edit ' .. fnameescape(path)
  return {project: project, session: project.scriveDir .. '/session.json'}
enddef

# FUNCTION: Return a field of the saved session, or 'missing', so that a
# write that did not happen fails its assertion instead of stopping the
# tests.
def Saved(fx: dict<any>, key: string): any
  return get(PE.ReadJson(fx.session), key, 'missing')
enddef

def Close(fx: dict<any>): void
  bwipe!
  ST.Set(null_object)
  SS.ForgetKnownStates()
  FI.CleanupProjectFiles(fx.project)
enddef

def Test_a_capture_writes_only_a_changed_state(): void
  var fx = OpenScene()
  cursor(2, 1)
  SS.CaptureCurDoc()
  assert_equal(2, Saved(fx, 'cursorLine'))
  # Nothing changed: no write, so the deleted file stays away.
  delete(fx.session)
  SS.CaptureCurDoc()
  assert_false(filereadable(fx.session))
  # The cursor moved: written again.
  cursor(3, 1)
  SS.CaptureCurDoc()
  assert_equal(3, Saved(fx, 'cursorLine'))
  Close(fx)
enddef

def Test_the_binder_state_writes_only_when_it_changes(): void
  var fx = OpenScene()
  SS.CaptureBinderState(true, ['a'])
  delete(fx.session)
  SS.CaptureBinderState(true, ['a'])
  assert_false(filereadable(fx.session))
  SS.CaptureBinderState(true, ['a', 'b'])
  assert_equal(['a', 'b'], Saved(fx, 'collapsedIds'))
  Close(fx)
enddef

# FUNCTION: The first capture reads session.json once, so that the fields
# of an earlier Vim session stay.
def Test_a_capture_keeps_the_fields_it_does_not_set(): void
  var fx = OpenScene()
  PE.WriteJson(fx.session, {binderOpen: true, collapsedIds: ['kept']})
  cursor(2, 1)
  SS.CaptureCurDoc()
  assert_equal([true, ['kept'], 2], [Saved(fx, 'binderOpen'), Saved(fx, 'collapsedIds'), Saved(fx, 'cursorLine')])
  Close(fx)
enddef

export def RunAll(): void
  Test_a_capture_writes_only_a_changed_state()
  Test_the_binder_state_writes_only_when_it_changes()
  Test_a_capture_keeps_the_fields_it_does_not_set()
enddef
