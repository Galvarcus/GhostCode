vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# snapshot.vim: manual checkpoints of one document's text. Not version
# control: no diffs and no branches, only copies that the author takes on
# purpose and can browse or restore later.
#
# Stored in <scrive>/snapshots/<doc-id>/<timestamp>.json, keyed by the
# document's id, which stays the same after a rename, unlike its path.
#
# Snapshot is defined before the functions that use it because List and
# Restore name it in a parameter or return type, and Vim9 resolves a
# signature when the function is defined.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/project.vim' as PO
import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/persist.vim' as PE
import autoload 'bartleby/log.vim' as L
import autoload 'bartleby/scrivenings.vim' as SV
import autoload 'bartleby/locale/common.vim' as MC
import autoload 'bartleby/locale/data.vim' as MD
import 'bartleby/variables/constants.vim' as CO

const STAMP_FMT: string = '%s-%s-%s %s:%s:%s'

var log = L.New(expand('<sfile>:t'))
var retention: number = g:bartleby_snapshot_retention

var id_counter: number = 0

def NewTimestamp(): string
  id_counter += 1
  return printf(CO.ID_FMT, strftime(CO.ID_TIME_FMT), id_counter)
enddef

export class Snap
  var timestamp: string = ''
  var label: string = ''
  var lines: list<string> = []

  static def FromDict(src: dict<any>): Snap
    var s: Snap = Snap.new()
    s.timestamp = get(src, 'timestamp', '')
    s.label = get(src, 'label', '')
    s.lines = get(src, 'lines', [])
    return s
  enddef

  def ToDict(): dict<any>
    return {timestamp: this.timestamp, label: this.label, lines: this.lines}
  enddef

  # METHOD: Return the name a picker shows: the label when one was given,
  # else the timestamp in readable form.
  def DisplayName(): string
    if this.label !=# ''
      return this.label
    endif
    var t: string = this.timestamp
    if strlen(t) >= 14
      return printf(STAMP_FMT, t[0 : 3], t[4 : 5], t[6 : 7], t[8 : 9], t[10 : 11], t[12 : 13])
    endif
    return t
  enddef
endclass

export def SnapDir(project: PO.Project, doc: BI.BinderItem): string
  return $'{project.scriveDir}/snapshots/{doc.id}'
enddef

def SnapPath(project: PO.Project, doc: BI.BinderItem, timestamp: string): string
  return $'{SnapDir(project, doc)}/{timestamp}.json'
enddef

# FUNCTION: Return the snapshots of doc, oldest first.
export def List(project: PO.Project, doc: BI.BinderItem): list<Snap>
  var dir: string = SnapDir(project, doc)
  if !isdirectory(dir)
    return []
  endif
  # nosuf true: wildignore is about which files to offer a writer, and
  # the snapshots of a document are not up for it.
  var files: list<string> = sort(globpath(dir, '*.json', true, true))
  return files->mapnew((_, f) => Snap.FromDict(PE.ReadJson(f)))
enddef

def EnforceRetention(project: PO.Project, doc: BI.BinderItem): void
  var snaps: list<Snap> = List(project, doc)
  var excess: number = len(snaps) - retention
  if excess <= 0
    return
  endif
  for i in range(excess)
    var path: string = SnapPath(project, doc, snaps[i].timestamp)
    if filereadable(path)
      delete(path)
    endif
  endfor
enddef

# FUNCTION: Take a snapshot of the text of doc that is on disk now. A
# caller that wants unsaved changes must write first. Take only copies
# the file and knows no buffers, so it works the same from the Binder and
# from an open buffer.
export def Take(project: PO.Project, doc: BI.BinderItem, label: string): void
  var path: string = doc.AbsPath(project.BinderRoot())
  if !filereadable(path)
    log.Error(MC.MissingFileDisk(path))
    return
  endif
  var v: dict<any> = {}
  v.timestamp = NewTimestamp()
  v.label = label
  v.lines = readfile(path)
  PE.WriteJson(SnapPath(project, doc, v.timestamp), v)
  EnforceRetention(project, doc)
  log.Info(MD.SnapTaken(doc.title, label ==# "" ? "" : $" ({label})"))
enddef

# FUNCTION: Replace the file of doc with the content of snapshot. First
# takes a snapshot of the current text, so a restore can always be
# undone. Reloads the buffer when the document is open, so the editor
# shows the restored text at once.
export def Restore(project: PO.Project, doc: BI.BinderItem, snap: Snap): void
  # The snapshot before the restore holds the text of an open Scrivening.
  SV.SaveIfModified()
  Take(project, doc, MD.BeforeRestore())
  var path: string = doc.AbsPath(project.BinderRoot())
  writefile(snap.lines, path)
  SV.SyncWithTree(project, true)
  # bufexists answers for the file itself. A path handed to bufnr answers
  # for that file too when a buffer holds it, but otherwise falls back to
  # reading the path as a pattern, which names any buffer whose own name
  # merely contains it, see bufname in builtin.txt. Reloading that one
  # would throw away text the writer had not saved.
  var winId: number = bufexists(path) ? bufwinid(bufnr(path)) : -1
  if winId != -1
    win_execute(winId, 'edit!')
  endif
  log.Info(MD.RestoredSnap(doc.title, snap.DisplayName()))
enddef
