vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# import_map.vim: reads the export of a project of another writing
# application and says what it means, so that import.vim can map it onto a
# scrive instead of taking it as any other folder.
#
# The export that this reads gives every item of the project a sidecar file
# beside it, <title> MetaData.txt, which holds the status, the label, the
# keywords, and the synopsis. A document that has notes gets a second
# sidecar, <title> Notes.<ext>, and a document that has snapshots gets a
# folder, <title> Snapshots. A plain folder import would take every one of
# those as a document or a folder of its own, so this script tells them
# apart: an item has a metadata file of its own, and a sidecar has none,
# which also leaves the snapshots folder behind.
#
# Nothing here reads a scrive or changes a file. Classify reads one folder,
# Detect and ProjectType read a few, and MetaFrom parses one file.
# License: GNU GPL 3.0
##############################################################################

import 'bartleby/variables/constants.vim' as CO

# The layout that Detect knows. An export of another layout gives an empty
# string and falls back to the plain folder import.
export const LAYOUT_SIDECAR: string = 'metadata-sidecars'

# The sidecars of one item, by the end of their name. The metadata file
# also takes the form <title> MetaData-2.txt, beside a document named
# <title>-2, where the export numbered two items of the same title.
const META_MARK: string = ' MetaData'
const NOTES_MARK: string = ' Notes'
const EXT_META: string = '.txt'
const META_PAT: string = ' MetaData\(-\d\+\)\?\.txt$'
# A number that the export added to tell two items of the same title apart.
const DEDUP_PAT: string = '-\d\+$'
# An order number in front of a title, which other exports write and this
# one does not. Stripped only when a title is left.
const ORDER_PAT: string = '^\d\+[-_. ]\+'
# How deep under the draft folder Detect looks for a metadata sidecar. A
# draft of parts of chapters of documents holds the first one three levels
# down, and no project nests the work deeper before its first document.
const META_DEPTH: number = 3

# The folder titles of the export that hold a known part of a project. A
# title that is not here, such as Places or Template Sheets, keeps its name
# and goes under Research, see import.vim.
const ROLE_TITLES: dict<string> = {
  manuscript: CO.ROLE_MANUSCRIPT,
  draft: CO.ROLE_MANUSCRIPT,
  screenplay: CO.ROLE_MANUSCRIPT,
  script: CO.ROLE_MANUSCRIPT,
  'front matter': CO.ROLE_FRONT_MATTER,
  'back matter': CO.ROLE_BACK_MATTER,
  characters: CO.ROLE_CHARS,
  people: CO.ROLE_CHARS,
  cast: CO.ROLE_CHARS,
  research: CO.ROLE_RESEARCH,
  trash: CO.ROLE_TRASH,
}

# The three statuses of the export that Bartleby names differently. Every
# other status has the name that Bartleby uses, see CO.STATUSES, and one
# that neither list holds becomes CO.NONE, so that a project with a status
# list of its own still imports.
const STATUS_ALIASES: dict<string> = {
  'No Status': CO.NONE,
  'In Progress': CO.STATUS_WORKING,
  'Revised Draft': CO.STATUS_REVISED,
}
const LABEL_NONE: string = 'No Label'

# The keys of a metadata file. Created and Modified are dropped, because
# Bartleby stores neither.
const KEY_CREATED: string = 'Created'
const KEY_MODIFIED: string = 'Modified'
const KEY_KEYWORDS: string = 'Keywords'
const KEY_PAT: string = '^\([^:]\+\): \?\(.*\)$'
# The writer can rename the status field and the label field, so the key of
# neither can be trusted. Their place can: the status comes first and the
# label second, once Created, Modified, and Keywords are out.
const IDX_STATUS: number = 0
const IDX_LABEL: number = 1
const SEP_KEYWORDS: string = ','

# CLASS: One item of an export: the file or folder that holds it, the title
# that it had in the binder, and its sidecars. metaPath is empty for a
# built-in top-level folder of the export, which carries no metadata file.
export class Item
  var path: string
  var title: string
  var isDir: bool
  var metaPath: string = ''
  var notesPath: string = ''

  def new(this.path, this.title, this.isDir, this.metaPath = v:none,
      this.notesPath = v:none)
  enddef
endclass

# CLASS: What one folder of an export holds: its items, in the order of the
# folder, and the paths that no import takes, such as a snapshots folder.
export class Listing
  var items: list<Item> = []
  var dropped: list<string> = []
  # The notes of the folder itself, which the export writes inside it
  # beside its metadata file.
  var ownNotes: string = ''

  def new(this.items = v:none, this.dropped = v:none, this.ownNotes = v:none)
  enddef
endclass

# CLASS: The metadata of one item of an export, with the status and the
# label already mapped onto the values that Bartleby stores.
export class Meta
  var status: string = CO.NONE
  var label: string = CO.NONE
  var keywords: list<string> = []
  var synopsis: string = ''

  def new(this.status = v:none, this.label = v:none,
      this.keywords = v:none, this.synopsis = v:none)
  enddef
endclass

# FUNCTION: Return the title that stem had in the binder: without an order
# number in front of it, and without the number that the export added when
# a sibling holds the same title. A number that no sibling explains is part
# of the title and stays.
def Titled(stem: string, stems: dict<bool>): string
  var title: string = substitute(stem, ORDER_PAT, '', '')
  if title ==# ''
    title = stem
  endif
  var bare: string = substitute(title, DEDUP_PAT, '', '')
  return bare !=# '' && bare !=# title && has_key(stems, bare) ? bare : title
enddef

# FUNCTION: Return the metadata file of the document named stem in dir, or
# an empty string when it has none and is therefore a sidecar of another
# item.
def DocMetaPath(dir: string, stem: string): string
  var plain: string = $'{dir}/{stem}{META_MARK}{EXT_META}'
  if filereadable(plain)
    return plain
  endif
  # A document named <title>-2 has its metadata in <title> MetaData-2.txt,
  # with the number at the end of the whole name.
  var num: string = matchstr(stem, DEDUP_PAT)
  if num ==# ''
    return ''
  endif
  var numbered: string = printf('%s/%s%s%s%s', dir,
    strpart(stem, 0, strlen(stem) - strlen(num)), META_MARK, num, EXT_META)
  return filereadable(numbered) ? numbered : ''
enddef

# FUNCTION: Return the metadata file that a folder holds for itself, or an
# empty string. The file keeps the title of the folder, so a folder named
# Part-2 holds Part MetaData.txt.
def FolderMetaPath(path: string): string
  var meta: string = printf('%s/%s%s%s', path,
    substitute(fnamemodify(path, ':t'), DEDUP_PAT, '', ''), META_MARK, EXT_META)
  return filereadable(meta) ? meta : ''
enddef

# FUNCTION: Return the role that the top-level folder titled title holds,
# or CO.ROLE_NONE when the export gives it no known part of a project.
export def RoleOf(title: string): string
  return get(ROLE_TITLES, tolower(title), CO.ROLE_NONE)
enddef

# FUNCTION: Return what dir holds: every item with its sidecars, and the
# paths that no import takes. A snapshots folder is dropped, because the
# export writes it in a form that a later release may change.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/38
export def Classify(dir: string): Listing
  var items: list<Item> = []
  var dropped: list<string> = []
  var ownNotes: string = ''
  var own: string = substitute(fnamemodify(dir, ':t'), DEDUP_PAT, '', '')
  var found: list<dict<any>> = []
  var orphans: list<string> = []
  var stems: dict<bool> = {}
  for name in readdir(dir)
    if name[0] ==# '.' || name =~# META_PAT
      continue
    endif
    var path: string = $'{dir}/{name}'
    var isDir: bool = isdirectory(path)
    var stem: string = isDir ? name : fnamemodify(name, ':t:r')
    var meta: string = isDir ? FolderMetaPath(path) : DocMetaPath(dir, stem)
    # A built-in top-level folder of the export, such as the draft or the
    # Trash, carries no metadata file and is still a folder of the project.
    if meta ==# '' && !(isDir && RoleOf(stem) !=# CO.ROLE_NONE)
      orphans->add(path)
      continue
    endif
    stems[stem] = true
    found->add({path: path, stem: stem, isDir: isDir, meta: meta})
  endfor
  # The notes of an item are found after it, so the items are built last.
  var notes: dict<string> = {}
  for path in orphans
    var owner: string = Owner(fnamemodify(path, ':t:r'), NOTES_MARK)
    if owner !=# '' && has_key(stems, owner)
      notes[owner] = path
    elseif owner !=# '' && owner ==# own
      ownNotes = path
    else
      dropped->add(path)
    endif
  endfor
  for f in found
    items->add(Item.new(f.path, Titled(f.stem, stems), f.isDir, f.meta,
      get(notes, f.stem, '')))
  endfor
  return Listing.new(items, dropped, ownNotes)
enddef

# FUNCTION: Return the name that stem is a sidecar of, when stem ends with
# mark, else an empty string.
def Owner(stem: string, mark: string): string
  if stem !~# $'{mark}$'
    return ''
  endif
  return strpart(stem, 0, strlen(stem) - strlen(mark))
enddef

# FUNCTION: Return the item of the draft folder of listing, where the work
# of the project is, or null_object when it holds none.
export def DraftOf(listing: Listing): Item
  for item in listing.items
    if item.isDir && RoleOf(item.title) ==# CO.ROLE_MANUSCRIPT
      return item
    endif
  endfor
  return null_object
enddef

# FUNCTION: Return true when dir holds a metadata sidecar, the mark of the
# export that this script reads.
export def HasMeta(dir: string): bool
  if !isdirectory(dir)
    return false
  endif
  return !empty(readdir(dir, (n) => n =~# META_PAT ? 1 : 0))
enddef

# FUNCTION: Return true when dir, or a folder within levels of it, holds a
# metadata sidecar.
def HasMetaWithin(dir: string, levels: number): bool
  if HasMeta(dir)
    return true
  endif
  if levels <= 0
    return false
  endif
  for name in readdir(dir, (n) => isdirectory($'{dir}/{n}') ? 1 : 0)
    if HasMetaWithin($'{dir}/{name}', levels - 1)
      return true
    endif
  endfor
  return false
enddef

# FUNCTION: Return the layout of the export at dir, or an empty string when
# it is not one that this script knows. An export has a draft folder and
# writes a metadata sidecar: at the top level, or, in a project of only
# built-in folders, no higher than the documents of a chapter of the draft.
export def Detect(dir: string): string
  if !isdirectory(dir)
    return ''
  endif
  var draft: Item = DraftOf(Classify(dir))
  if draft is null_object
    return ''
  endif
  return HasMeta(dir) || HasMetaWithin(draft.path, META_DEPTH)
    ? LAYOUT_SIDECAR
    : ''
enddef

# FUNCTION: Return the folders of dir, by the listing of dir.
def FoldersOf(dir: string): list<Item>
  return Classify(dir).items->copy()->filter((_, i) => i.isDir)
enddef

# FUNCTION: Return the scrive type that the export at dir needs: a
# screenplay from its Fountain text, else from the depth of its draft,
# where folders of folders are parts, folders of documents are chapters,
# and documents alone are a short story. An empty string when dir has no
# draft folder.
export def ProjectType(dir: string): string
  var draft: Item = DraftOf(Classify(dir))
  if draft is null_object
    return ''
  endif
  if !empty(globpath(draft.path, $'**/*{CO.EXT_FOUNTAIN}', true, true))
    return CO.TYPE_SCREENPLAY
  endif
  var folders: list<Item> = FoldersOf(draft.path)
  if empty(folders)
    return CO.TYPE_SHORT_STORY
  endif
  for f in folders
    if !empty(FoldersOf(f.path))
      return CO.TYPE_NOVEL_PARTS
    endif
  endfor
  return CO.TYPE_NOVEL
enddef

# FUNCTION: Return the value of values that known or aliases holds, else
# the one at idx, else an empty string. A renamed field is found by its
# value, and a renamed value by its place.
def Pick(values: list<string>, known: list<string>, aliases: dict<string>,
    idx: number): string
  for v in values
    if index(known, v) >= 0 || has_key(aliases, v)
      return v
    endif
  endfor
  return idx < len(values) ? values[idx] : ''
enddef

# FUNCTION: Return the Bartleby status for the status value of an export.
def StatusOf(value: string): string
  if has_key(STATUS_ALIASES, value)
    return STATUS_ALIASES[value]
  endif
  return index(CO.STATUSES, value) >= 0 ? value : CO.NONE
enddef

# FUNCTION: Return the Bartleby label for the label value of an export. The
# colors carry the names that Bartleby uses, so only the empty one and an
# unknown one are mapped.
def LabelOf(value: string): string
  if value ==# LABEL_NONE
    return CO.NONE
  endif
  return index(CO.LABELS, value) >= 0 ? value : CO.NONE
enddef

# FUNCTION: Return lines without the empty lines at either end, which the
# export writes between the fields and the synopsis.
def Trimmed(lines: list<string>): list<string>
  var first: number = 0
  var last: number = len(lines) - 1
  while first <= last && trim(lines[first]) ==# ''
    first += 1
  endwhile
  while last >= first && trim(lines[last]) ==# ''
    last -= 1
  endwhile
  return first > last ? [] : lines[first : last]
enddef

# FUNCTION: Return the metadata that the file at path holds. The status and
# the label are read by their value, because the writer can rename both
# fields, and by their place, because the writer can rename both values.
# The synopsis is the free text under the fields.
export def MetaFrom(path: string): Meta
  if !filereadable(path)
    return Meta.new()
  endif
  var values: list<string> = []
  var keywords: list<string> = []
  var rest: list<string> = []
  for line in readfile(path)
    var parts: list<string> = matchlist(line, KEY_PAT)
    if empty(parts) || !empty(rest)
      rest->add(line)
      continue
    endif
    if parts[1] ==# KEY_CREATED || parts[1] ==# KEY_MODIFIED
      continue
    endif
    if parts[1] ==# KEY_KEYWORDS
      keywords = split(parts[2], SEP_KEYWORDS)
        ->mapnew((_, k) => trim(k))
        ->filter((_, k) => k !=# '')
      continue
    endif
    values->add(parts[2])
  endfor
  return Meta.new(
    StatusOf(Pick(values, CO.STATUSES, STATUS_ALIASES, IDX_STATUS)),
    LabelOf(Pick(values, CO.LABELS, {[LABEL_NONE]: CO.NONE}, IDX_LABEL)),
    keywords, join(Trimmed(rest), "\n"))
enddef
