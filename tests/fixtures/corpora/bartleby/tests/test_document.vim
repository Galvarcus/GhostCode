vim9script
##############################################################################
# Plugin_Name: Bartleby
# tests/test_document.vim: DocMeta of document.vim, converted to and from
# dicts, and its setters. FromDict and ToDict work in memory. Load and
# Save are the only tests here that use a real file on disk, and they
# remove it.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/document.vim' as D
import 'bartleby/variables/constants.vim' as CO

def Test_new_docmeta_has_sensible_defaults(): void
  var meta = D.DocMeta.new()
  assert_equal('None', meta.label)
  # A document that nobody has marked has no status, as it has no label.
  # REFERENCE: https://github.com/Galvarcus/bartleby/issues/42
  assert_equal('None', meta.status)
  assert_equal('', meta.synopsis)
  assert_equal([], meta.keywords)
  assert_equal(0, meta.wordCountTarget)
  assert_equal({}, meta.custom)
enddef

def Test_from_dict_reads_every_field(): void
  var meta = D.DocMeta.FromDict({
    label: 'Red', status: 'Revised', synopsis: 'A summary.',
    keywords: ['fish', 'river'], wordCountTarget: 5000, custom: {note: 'x'},
  })
  assert_equal('Red', meta.label)
  assert_equal('Revised', meta.status)
  assert_equal('A summary.', meta.synopsis)
  assert_equal(['fish', 'river'], meta.keywords)
  assert_equal(5000, meta.wordCountTarget)
  assert_equal({note: 'x'}, meta.custom)
enddef

def Test_from_dict_tolerates_missing_keys(): void
  # An older or partial metadata file with only a label.
  var meta = D.DocMeta.FromDict({label: 'Blue'})
  assert_equal('Blue', meta.label)
  assert_equal('None', meta.status)
  assert_equal([], meta.keywords)
enddef

def Test_to_dict_round_trips_through_from_dict(): void
  var original = D.DocMeta.new()
  original.SetLabel('Green')
  original.SetStatus('Done')
  original.SetSynopsis("Line one.\nLine two.")
  original.SetKeywords(['a', 'b', 'c'])
  original.SetWordCountTarget(2500)
  var restored = D.DocMeta.FromDict(original.ToDict())
  assert_equal(original.label, restored.label)
  assert_equal(original.status, restored.status)
  assert_equal(original.synopsis, restored.synopsis)
  assert_equal(original.keywords, restored.keywords)
  assert_equal(original.wordCountTarget, restored.wordCountTarget)
enddef

def Test_setters_mutate_only_their_own_field(): void
  var meta = D.DocMeta.new()
  meta.SetLabel('Purple')
  assert_equal('Purple', meta.label)
  # Not changed.
  assert_equal('None', meta.status)
enddef

def Test_load_of_a_missing_sidecar_yields_plain_defaults(): void
  var meta = D.DocMeta.Load('/tmp/bartleby-test-nonexistent-sidecar.json')
  assert_equal('None', meta.label)
  assert_equal(0, meta.wordCountTarget)
enddef

def Test_save_then_load_round_trips_to_disk(): void
  var path = tempname() .. '.meta.json'
  var meta = D.DocMeta.new()
  meta.SetLabel('Orange')
  meta.SetWordCountTarget(1200)
  meta.SetKeywords(['x', 'y'])
  meta.Save(path)
  var reloaded = D.DocMeta.Load(path)
  assert_equal('Orange', reloaded.label)
  assert_equal(1200, reloaded.wordCountTarget)
  assert_equal(['x', 'y'], reloaded.keywords)
  delete(path)
enddef

# FUNCTION: The display names must cover exactly the stored values, so a
# label or status added to constants.vim also needs a name.
def Test_display_names_cover_the_stored_values(): void
  assert_equal(sort(copy(CO.LABELS)), sort(keys(D.LabelNames())))
  assert_equal(sort(copy(CO.STATUSES)), sort(keys(D.StatusNames())))
  assert_equal('Red', D.LabelName('Red'))
  assert_equal('Unknown', D.LabelName('Unknown'))
enddef

# FUNCTION: The two steps that an import needs and that the list had no
# room for before: text that is not a draft yet, and a draft that is
# finished but not released.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/42
def Test_the_status_list_holds_every_step_in_order(): void
  assert_equal(['None', 'To Do', 'Working Draft', 'First Draft', 'Revised',
    'Final Draft', 'Done'], CO.STATUSES)
  assert_equal('Working Draft', D.StatusName('Working Draft'))
  assert_equal('Final Draft', D.StatusName('Final Draft'))
enddef

export def RunAll(): void
  Test_new_docmeta_has_sensible_defaults()
  Test_from_dict_reads_every_field()
  Test_from_dict_tolerates_missing_keys()
  Test_to_dict_round_trips_through_from_dict()
  Test_setters_mutate_only_their_own_field()
  Test_load_of_a_missing_sidecar_yields_plain_defaults()
  Test_save_then_load_round_trips_to_disk()
  Test_display_names_cover_the_stored_values()
  Test_the_status_list_holds_every_step_in_order()
enddef
