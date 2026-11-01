vim9script
##############################################################################
# Plugin_Name: Bartleby
# tests/test_autosave.vim: autosave.vim saves only changed documents of
# the open scrive, keeps the interval, always saves when forced, runs a
# deferred save when the interval ends, and does nothing when turned off.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/autosave.vim' as A
import autoload 'bartleby/project.vim' as PO
import autoload 'bartleby/state.vim' as ST
import 'bartleby/variables/constants.vim' as CO
import './fixtures.vim' as FI

def Setup(): dict<any>
  var root: string = FI.TempPath()
  var project = PO.Project.new(root .. '/Test.bartleby')
  project.InitNew('Test', CO.TYPE_NOVEL)
  ST.Set(project)
  var doc: string = project.BinderRoot() .. '/scene.md'
  mkdir(fnamemodify(doc, ':h'), 'p')
  writefile(['start'], doc)
  var outside: string = root .. '/notes.md'
  writefile(['start'], outside)
  return {root: root, doc: doc, outside: outside}
enddef

def Teardown(fx: dict<any>): void
  silent! bwipe!
  g:bartleby_autosave = true
  g:bartleby_autosave_interval = 30
  delete(fx.root, 'rf')
enddef

def Edit(text: string): void
  setline(1, text)
enddef

def Test_saves_a_changed_scrive_document(): void
  var fx = Setup()
  execute 'edit ' .. fx.doc
  assert_true(A.IsScriveDoc())
  Edit('changed')
  A.Save(false)
  assert_equal(['changed'], readfile(fx.doc))
  assert_false(&modified)
  Teardown(fx)
enddef

def Test_ignores_files_outside_the_binder(): void
  var fx = Setup()
  execute 'edit ' .. fx.outside
  assert_false(A.IsScriveDoc())
  Edit('changed')
  A.Save(true)
  assert_equal(['start'], readfile(fx.outside))
  Teardown(fx)
enddef

def Test_interval_skips_then_force_saves(): void
  var fx = Setup()
  execute 'edit ' .. fx.doc
  Edit('first')
  A.Save(false)
  Edit('second')
  A.Save(false)
  assert_equal(['first'], readfile(fx.doc))
  assert_true(get(b:, 'bartleby_autosave_pending', false))
  A.Save(true)
  assert_equal(['second'], readfile(fx.doc))
  Teardown(fx)
enddef

# FUNCTION: A skipped save runs by itself when the interval ends. The
# interval is 2 seconds, not 1: localtime counts whole seconds, and with 1
# second a clock tick between the two saves would let the second save
# write at once. The wait is 3.5 seconds, because with whole seconds the
# timer can need one more round.
def Test_deferred_save_runs_when_the_interval_ends(): void
  var fx = Setup()
  g:bartleby_autosave_interval = 2
  execute 'edit ' .. fx.doc
  Edit('first')
  A.Save(false)
  Edit('second')
  A.Save(false)
  assert_equal(['first'], readfile(fx.doc))
  sleep 3500m
  assert_equal(['second'], readfile(fx.doc))
  Teardown(fx)
enddef

def Test_does_nothing_when_turned_off(): void
  var fx = Setup()
  g:bartleby_autosave = false
  execute 'edit ' .. fx.doc
  Edit('changed')
  A.Save(true)
  assert_equal(['start'], readfile(fx.doc))
  Teardown(fx)
enddef

def Test_keeps_change_marks(): void
  var fx = Setup()
  execute 'edit ' .. fx.doc
  append(1, ['two', 'three'])
  var before = [line("'["), line("']")]
  A.Save(true)
  assert_equal(before, [line("'["), line("']")])
  Teardown(fx)
enddef

export def RunAll(): void
  Test_saves_a_changed_scrive_document()
  Test_ignores_files_outside_the_binder()
  Test_interval_skips_then_force_saves()
  Test_deferred_save_runs_when_the_interval_ends()
  Test_does_nothing_when_turned_off()
  Test_keeps_change_marks()
enddef
