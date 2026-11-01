vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# document.vim: the metadata of a document: label, status, synopsis,
# keywords, word count target, and custom fields. Kept apart from
# BinderItem so that it loads only when needed: the Binder does not use
# it, the Corkboard, Outliner, and Inspector do. Saved as a JSON file
# next to the document's text file.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/persist.vim' as PE
import autoload 'bartleby/locale/data.vim' as MD
import 'bartleby/variables/constants.vim' as CO

# FUNCTION: Return each label, as stored in CO.LABELS, to its name in the
# message language. The stored value stays English, so a scrive keeps its
# labels in any language. tests/test_document.vim checks that the keys
# match CO.LABELS.
export def LabelNames(): dict<string>
  return {
    [CO.NONE]: MD.None(),
    Red: MD.Red(),
    Orange: MD.Orange(),
    Yellow: MD.Yellow(),
    Green: MD.Green(),
    Blue: MD.Blue(),
    Purple: MD.Purple(),
  }
enddef

# FUNCTION: Return each status, as stored in CO.STATUSES, to its name in
# the message language, as LabelNames does for labels.
export def StatusNames(): dict<string>
  return {
    [CO.NONE]: MD.None(),
    [CO.STATUS_TODO]: MD.Do(),
    [CO.STATUS_WORKING]: MD.WorkingDraft(),
    [CO.STATUS_FIRST]: MD.FirstDraft(),
    [CO.STATUS_REVISED]: MD.Revised(),
    [CO.STATUS_FINAL]: MD.FinalDraft(),
    [CO.STATUS_DONE]: MD.Done(),
  }
enddef

# FUNCTION: Return the shown name of a stored label or status.
export def LabelName(label: string): string
  return get(LabelNames(), label, label)
enddef

export def StatusName(status: string): string
  return get(StatusNames(), status, status)
enddef

export class DocMeta
  var label: string = CO.NONE
  var status: string = CO.NONE
  var synopsis: string = ''
  var keywords: list<string> = []
  var wordCountTarget: number = 0
  var custom: dict<any> = {}

  # METHOD: Build a DocMeta from a decoded JSON dict. Missing keys get
  # defaults, so older or partial files still load.
  static def FromDict(src: dict<any>): DocMeta
    var meta: DocMeta = DocMeta.new()
    meta.label = get(src, 'label', CO.NONE)
    meta.status = get(src, 'status', CO.NONE)
    meta.synopsis = get(src, 'synopsis', '')
    meta.keywords = get(src, 'keywords', [])
    meta.wordCountTarget = get(src, 'wordCountTarget', 0)
    meta.custom = get(src, 'custom', {})
    return meta
  enddef

  def ToDict(): dict<any>
    return {
      label: this.label,
      status: this.status,
      synopsis: this.synopsis,
      keywords: this.keywords,
      wordCountTarget: this.wordCountTarget,
      custom: this.custom,
    }
  enddef

  # METHOD: Load the metadata file at sidecarPath, an absolute path. A
  # missing file gives the defaults, not an error: a document without
  # metadata is normal.
  static def Load(sidecarPath: string): DocMeta
    if !filereadable(sidecarPath)
      return DocMeta.new()
    endif
    return DocMeta.FromDict(PE.ReadJson(sidecarPath))
  enddef

  def Save(sidecarPath: string): void
    PE.WriteJson(sidecarPath, this.ToDict())
  enddef

  # METHOD: Set the label. Fields are written only inside the class, error
  # E1335.
  def SetLabel(newLabel: string): void
    this.label = newLabel
  enddef

  def SetStatus(newStatus: string): void
    this.status = newStatus
  enddef

  def SetSynopsis(newSynopsis: string): void
    this.synopsis = newSynopsis
  enddef

  def SetKeywords(newKeywords: list<string>): void
    this.keywords = newKeywords
  enddef

  # METHOD: Set the word count target, which the Inspector's Target field
  # edits. 0 means no target.
  def SetWordCountTarget(target: number): void
    this.wordCountTarget = target
  enddef
endclass
