vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# import.vim: brings files and folders from outside a scrive into it. Each
# file is copied into the binder folder and gets a document in the Binder,
# titled from the file name, and each folder gets a Binder folder that
# holds what was in it. The copy holds the bytes of the source and takes
# the document extension of the scrive, which Recover, Tidy, and Compile
# need to find it. The source stays where it is.
#
# An import runs in two steps. Plan works out what would come in, without
# changing anything, so that the caller can report the counts and ask
# first. Apply then adds it. A file that the scrive type does not accept,
# that cannot be read, or that is already in the scrive is skipped and
# counted, so that one file cannot stop an import.
#
# A folder that holds the export of a project of another writing
# application is read as that project, not as a plain tree: import_map.vim
# recognizes it, and then each known folder of the export goes into the
# scrive folder of the same role, with the status, the label, the keywords,
# and the synopsis of every document. Plan and Apply take that path by
# themselves, so a caller needs to know nothing about it.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/38
#
# No UI and no saving: binder.vim asks, saves the project, and draws the
# Binder again, see ImportPaths there.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/document.vim' as D
import autoload 'bartleby/import_map.vim' as IMM
import autoload 'bartleby/layout.vim' as LY
import autoload 'bartleby/mutate.vim' as MU
import autoload 'bartleby/project.vim' as PO
import autoload 'bartleby/tree.vim' as T
import autoload 'bartleby/locale/binder.vim' as MB
import autoload 'bartleby/path.vim' as PA
import 'bartleby/variables/constants.vim' as CO

# Between the parts of a report, and between the skipped names in it.
const SEP: string = ', '
# Each run of digits in a sort key is padded to this width, which holds
# every number that Vim can count, so that a plain compare of two keys
# gives the natural order.
const NUM_FMT: string = '%020d'
# How many names a report shows before it leaves the rest to the count,
# which a project export of a format that Bartleby cannot read needs.
const MAX_NAMES: number = 5
const MORE: string = '...'

# FUNCTION: Return the name of the folder at dir, without the trailing
# slash that ExpandPaths leaves on a folder.
def FolderName(dir: string): string
  return fnamemodify(substitute(dir, '[/\\]$', '', ''), ':t')
enddef

# FUNCTION: Return a sort key for name, with each run of digits padded,
# so that Chapter 2 comes before Chapter 10.
def SortKey(name: string): string
  return substitute(name, '\d\+', '\=printf(NUM_FMT, str2nr(submatch(0)))', 'g')
enddef

# FUNCTION: Return names in their natural order, see SortKey.
def Sorted(names: list<string>): list<string>
  return names
    ->mapnew((_, n) => [SortKey(n), n])
    ->sort((a, b) => a[0] ==# b[0] ? 0 : a[0] ># b[0] ? 1 : -1)
    ->mapnew((_, keyed) => keyed[1])
enddef

# FUNCTION: Return items in the natural order of their names, without the
# extension, so that a second item of one title follows the first: Scene
# comes before Scene-2, which the extension would otherwise reverse,
# because a dot sorts after a hyphen.
def Ordered(items: list<IMM.Item>): list<IMM.Item>
  return items
    ->mapnew((_, i) => [SortKey(fnamemodify(i.path, i.isDir ? ':t' : ':t:r')), i])
    ->sort((a, b) => a[0] ==# b[0] ? 0 : a[0] ># b[0] ? 1 : -1)
    ->mapnew((_, keyed) => keyed[1])
enddef

# FUNCTION: Return true when a sibling before item holds the title of
# item, so that the first of two items of one title keeps it.
def Repeats(siblings: list<BI.BinderItem>, item: BI.BinderItem): bool
  for s in siblings
    if s.id ==# item.id
      return false
    endif
    if s.title ==# item.title
      return true
    endif
  endfor
  return false
enddef

# FUNCTION: Return the names of up to MAX_NAMES paths, so that a report of
# a whole project that was skipped stays readable. The message holds the
# full count.
def Names(paths: list<string>): string
  var shown: list<string> = paths[0 : MAX_NAMES - 1]
    ->mapnew((_, p) => fnamemodify(p, ':t'))
  if len(paths) > MAX_NAMES
    shown->add(MORE)
  endif
  return join(shown, SEP)
enddef

# FUNCTION: Return each path absolute, with its home directory and its
# wildcards expanded, in the order given. A path that matches nothing
# stays as it is, so that the import reports it by the name that the user
# gave.
export def ExpandPaths(paths: list<string>): list<string>
  var found: list<string> = []
  for path in paths
    # Nosuf, so that a wildignore of the user cannot drop a file that the
    # user named for the import.
    var matches: list<string> = glob(path, true, true)
    found += (empty(matches) ? [path] : matches)->mapnew((_, p) => fnamemodify(p, ':p'))
  endfor
  return found
enddef

# CLASS: One import into one scrive: the extensions that it accepts, what
# Plan found, the documents that Apply added, and the sources that it
# skipped.
export class Importer
  var project: PO.Project
  # The accepted extensions of the scrive type, lowercase.
  var exts: list<string>
  # What Plan found, in the order of the paths. Each entry is a document,
  # with its path, or a folder, with its item tree and the source file of
  # each document in it, by item id.
  var entries: list<dict<any>> = []
  # How many documents and folders Plan found, for the question that the
  # caller asks before Apply.
  var docs: number = 0
  var folders: number = 0
  var added: list<BI.BinderItem> = []
  var skipped: list<string> = []
  # The layout that import_map.vim found, empty for a plain import.
  var layout: string = ''
  # What a project import would add, by the role of the scrive folder that
  # takes it. Each entry holds children, sources, and metas.
  var _groups: list<dict<any>> = []
  # The notes sidecars of a project export, each a title and a path, which
  # become documents of one folder under Research.
  var _notes: list<dict<string>> = []
  # How many sources were skipped for their format, which the writer can
  # fix with a new export.
  var _badFormat: number = 0

  def new(this.project)
    this.exts = this.project.projectType ==# CO.TYPE_SCREENPLAY
      ? CO.IMPORT_EXTS_SCREENPLAY
      : CO.IMPORT_EXTS_TEXT
  enddef

  # METHOD: Return true when this scrive takes path: a readable file, with
  # an accepted extension, outside the scrive.
  def Accepts(path: string): bool
    return filereadable(path)
      && index(this.exts, '.' .. tolower(fnamemodify(path, ':e'))) >= 0
      && !this._Inside(path)
  enddef

  # METHOD: Work out what an import of paths would add, and change
  # nothing. A folder that holds no file that this scrive takes is
  # skipped, as a file of the wrong kind is.
  def Plan(paths: list<string>): void
    if len(paths) == 1 && isdirectory(paths[0])
      this.layout = IMM.Detect(paths[0])
      if this.layout !=# ''
        this._PlanProject(paths[0])
        return
      endif
    endif
    for path in paths
      if isdirectory(path)
        var scan: dict<any> = this._ScanFolder(path)
        if empty(scan)
          this.skipped->add(path)
          continue
        endif
        this.entries->add({kind: CO.KIND_FOLDER, item: scan.item, sources: scan.sources})
        this.docs += scan.docs
        this.folders += scan.folders
      elseif this.Accepts(path)
        this.entries->add({kind: CO.KIND_DOC, path: path})
        this.docs += 1
      else
        this._Skip(path)
      endif
    endfor
  enddef

  # METHOD: Add what Plan found next to row: into row when it is a folder,
  # else after it, where a new document goes. Each entry goes after the
  # one before it, so that the Binder keeps the order of the paths.
  def Apply(row: T.Row): void
    if this.layout !=# ''
      this._ApplyGroups()
      return
    endif
    var anchor: T.Row = row
    for entry in this.entries
      var item: BI.BinderItem = entry.kind ==# CO.KIND_FOLDER
        ? this._AddTree(anchor, entry)
        : this._AddFile(anchor, entry.path)
      anchor = T.FindRowById(T.Flatten(this.project), item.id)
    endfor
  enddef

  # METHOD: Import each path, in the order given, next to row. Plan and
  # Apply in one call, for an import that needs no question first.
  def Files(row: T.Row, paths: list<string>): void
    this.Plan(paths)
    this.Apply(row)
  enddef

  # METHOD: Return what this import did, for its caller to report.
  def Report(): string
    var parts: list<string> = []
    if this.layout !=# ''
      parts->add(MB.ReadAsProject())
    endif
    parts->add(MB.ImportedDoc(len(this.added)))
    if this.folders > 0
      parts->add(MB.FolderAdded(this.folders))
    endif
    if !empty(this.skipped)
      parts->add(MB.SkippedFile(len(this.skipped), Names(this.skipped)))
    endif
    # Only a project export is advised to come again: a writer who named
    # one file of the wrong kind can see that from the name.
    if this.layout !=# '' && this._badFormat > 0
      parts->add(MB.ExportAsText())
    endif
    return join(parts, SEP)
  enddef

  # METHOD: Count path as skipped, and as a format that a new export could
  # fix when it is a file of a kind that this scrive does not take.
  def _Skip(path: string): void
    this.skipped->add(path)
    if !isdirectory(path) && index(this.exts,
        '.' .. tolower(fnamemodify(path, ':e'))) < 0
      this._badFormat += 1
    endif
  enddef

  # METHOD: Work out what an import of the project export at dir would add.
  # The children of a folder that the export gives a role go into the
  # scrive folder of that role, so that the draft of the project lands in
  # the Manuscript and its characters in Characters. A folder that the
  # export gives no role, such as its places or its template sheets, keeps
  # its name under Research, and so does a document at the top level. The
  # Trash is left behind.
  def _PlanProject(dir: string): void
    var listing: IMM.Listing = IMM.Classify(dir)
    for path in listing.dropped
      this._Skip(path)
    endfor
    for item in Ordered(listing.items)
      var role: string = IMM.RoleOf(item.title)
      if role ==# CO.ROLE_TRASH
        continue
      endif
      if !item.isDir
        this._PlanTop(CO.ROLE_RESEARCH, item, false)
      elseif role ==# CO.ROLE_NONE
        this._PlanTop(CO.ROLE_RESEARCH, item, true)
      else
        this._PlanTop(role, item, false)
      endif
    endfor
    this._PlanNotes()
  enddef

  # METHOD: Plan one top-level item of an export into the scrive folder
  # with role: the folder itself when whole is true, else what it holds. A
  # document is planned on its own.
  def _PlanTop(role: string, item: IMM.Item, whole: bool): void
    if !item.isDir
      if !this.Accepts(item.path)
        this._Skip(item.path)
        return
      endif
      var doc: BI.BinderItem = BI.BinderItem.NewDocument(item.title, '')
      var sources: dict<string> = {}
      sources[doc.id] = item.path
      var metas: dict<string> = {}
      if item.metaPath !=# ''
        metas[doc.id] = item.metaPath
      endif
      if item.notesPath !=# ''
        this._notes->add({title: item.title, path: item.notesPath})
      endif
      this._AddGroup(role, [doc], sources, metas)
      this.docs += 1
      return
    endif
    var scan: dict<any> = this._ScanExport(item.path)
    if scan.docs == 0
      return
    endif
    var children: list<BI.BinderItem> = scan.children
    var folders: number = scan.folders
    if whole
      var folder: BI.BinderItem = BI.BinderItem.NewFolder(item.title)
      folder.SetChildren(scan.children)
      children = [folder]
      folders += 1
    endif
    this._AddGroup(role, children, scan.sources, scan.metas)
    this.docs += scan.docs
    this.folders += folders
  enddef

  # METHOD: Plan the notes of every document of the export as documents of
  # one folder under Research. Bartleby holds the synopsis of a document in
  # its metadata and its notes nowhere, so the text becomes a document of
  # its own, out of the Manuscript, where no compile reads it.
  def _PlanNotes(): void
    var children: list<BI.BinderItem> = []
    var sources: dict<string> = {}
    for note in this._notes
      if !this.Accepts(note.path)
        this._Skip(note.path)
        continue
      endif
      var doc: BI.BinderItem = BI.BinderItem.NewDocument(note.title, '')
      children->add(doc)
      sources[doc.id] = note.path
    endfor
    if empty(children)
      return
    endif
    var folder: BI.BinderItem = BI.BinderItem.NewFolder(MB.DocNotes())
    folder.SetChildren(children)
    this._AddGroup(CO.ROLE_RESEARCH, [folder], sources, {})
    this.docs += len(children)
    this.folders += 1
  enddef

  # METHOD: Add children to the group of role, which holds everything that
  # one folder of the scrive takes, so that the Research folder takes the
  # research of the export, its loose folders, and the notes in one place.
  def _AddGroup(role: string, children: list<BI.BinderItem>,
      sources: dict<string>, metas: dict<string>): void
    for group in this._groups
      if group.role ==# role
        group.children += children
        group.sources->extend(sources)
        group.metas->extend(metas)
        return
      endif
    endfor
    this._groups->add({role: role, children: children, sources: sources,
      metas: metas})
  enddef

  # METHOD: Return what the export folder at dir holds, as Binder items
  # with the source file and the metadata file of every document. A folder
  # that holds no document that this scrive takes is left out, as in a
  # plain import, and a sidecar is never an item of its own.
  def _ScanExport(dir: string): dict<any>
    var listing: IMM.Listing = IMM.Classify(dir)
    var children: list<BI.BinderItem> = []
    var sources: dict<string> = {}
    var metas: dict<string> = {}
    var docs: number = 0
    var folders: number = 0
    for path in listing.dropped
      this._Skip(path)
    endfor
    if listing.ownNotes !=# ''
      this._notes->add({title: FolderName(dir), path: listing.ownNotes})
    endif
    for item in Ordered(listing.items)
      if item.isDir
        var sub: dict<any> = this._ScanExport(item.path)
        if sub.docs == 0
          continue
        endif
        var folder: BI.BinderItem = BI.BinderItem.NewFolder(item.title)
        folder.SetChildren(sub.children)
        children->add(folder)
        sources->extend(sub.sources)
        metas->extend(sub.metas)
        docs += sub.docs
        folders += 1 + sub.folders
        continue
      endif
      if !this.Accepts(item.path)
        this._Skip(item.path)
        continue
      endif
      var doc: BI.BinderItem = BI.BinderItem.NewDocument(item.title, '')
      children->add(doc)
      sources[doc.id] = item.path
      if item.metaPath !=# ''
        metas[doc.id] = item.metaPath
      endif
      if item.notesPath !=# ''
        this._notes->add({title: item.title, path: item.notesPath})
      endif
      docs += 1
    endfor
    return {children: children, sources: sources, metas: metas, docs: docs,
      folders: folders}
  enddef

  # METHOD: Add every group to the scrive folder of its role, at the end of
  # what is already there. A scrive without that folder, older than roles,
  # takes the items at the top level.
  def _ApplyGroups(): void
    for group in this._groups
      var target: BI.BinderItem = MU.FindTopWithRole(this.project, group.role)
      var row: T.Row = target is null_object
        ? null_object
        : T.FindRowById(T.Flatten(this.project), target.id)
      for child in group.children
        MU.AddNear(this.project, row, child)
        if child.IsFolder()
          # The roles come before the paths, as in a plain import, and the
          # numbers before the paths as well, because a folder takes its
          # place on disk from its title.
          this._SetRoles(child, target)
          this._Renumber(child, target is null_object
            ? this.project.items
            : target.children)
        endif
        LY.Place(this.project, child)
        this._WriteItem(child, group.sources, group.metas)
      endfor
    endfor
  enddef

  # METHOD: Give a Part or a Chapter whose title repeats a sibling's the
  # next free number, as an unnamed one gets from MU.NextRoleNum, and so
  # down the tree. The export numbers the second item of a title itself,
  # Part-2, but that number is not a title, see import_map.vim, and two
  # folders of one title would share a folder on disk.
  def _Renumber(item: BI.BinderItem, siblings: list<BI.BinderItem>): void
    if (item.structureRole ==# CO.ROLE_PART
        || item.structureRole ==# CO.ROLE_CHAPTER)
        && Repeats(siblings, item)
      item.Rename(MU.NextRoleNum(siblings, item.structureRole))
    endif
    for child in item.children
      if child.IsFolder()
        this._Renumber(child, item.children)
      endif
    endfor
  enddef

  # METHOD: Copy the file of item, or of every document in it, and write
  # the metadata that the export held for each.
  def _WriteItem(item: BI.BinderItem, sources: dict<string>,
      metas: dict<string>): void
    if item.IsFolder()
      for child in item.children
        this._WriteItem(child, sources, metas)
      endfor
      return
    endif
    this._WriteCopy(sources[item.id], item)
    if has_key(metas, item.id)
      this._WriteMeta(item, metas[item.id])
    endif
    this.added->add(item)
  enddef

  # METHOD: Write the status, the label, the keywords, and the synopsis
  # that the export held for doc. The file follows the document, so this
  # runs after LY.Place has given it its path.
  def _WriteMeta(doc: BI.BinderItem, metaPath: string): void
    var found: IMM.Meta = IMM.MetaFrom(metaPath)
    var root: string = this.project.BinderRoot()
    var meta: D.DocMeta = doc.LoadMeta(root)
    meta.SetStatus(found.status)
    meta.SetLabel(found.label)
    meta.SetKeywords(found.keywords)
    if found.synopsis !=# ''
      meta.SetSynopsis(found.synopsis)
    endif
    meta.Save(doc.MetaPath(root))
  enddef

  # METHOD: Return the tree that an import of dir would add: its folder
  # item with everything inside it, the source file of each document by
  # item id, and how many documents and folders it holds. Names are taken
  # in their natural order, and a hidden name, a file that this scrive
  # does not take, and a folder that is a symbolic link, which could lead
  # back into the tree, are skipped. A folder that holds no document is
  # left out, and gives an empty dict.
  def _ScanFolder(dir: string): dict<any>
    var children: list<BI.BinderItem> = []
    var sources: dict<string> = {}
    var docs: number = 0
    var folders: number = 1
    for name in Sorted(readdir(dir))
      var path: string = $'{dir}/{name}'
      if name[0] ==# '.'
        continue
      endif
      if isdirectory(path)
        # A folder that is a link could lead back into the tree. getftype
        # answers link for one on Unix, and Windows makes a reparse point
        # that it does not always name that way, so a resolve that moves
        # the last part of the path is a link as well. The parent is
        # resolved too, because a link above the source, as /tmp is on
        # macOS, must not make every folder under it look like one. The
        # comparison goes through path.vim, since resolve answers with the
        # separator and the case of the system and two spellings of one
        # folder would read as a link, and the name on the right stays
        # unresolved, which is the test itself.
        # REFERENCE: https://github.com/Galvarcus/bartleby/issues/50
        if getftype(path) ==# 'link'
            || PA.Canon(path) !=# PA.CanonUnresolved($'{resolve(dir)}/{name}')
          this.skipped->add(path)
          continue
        endif
        var sub: dict<any> = this._ScanFolder(path)
        if empty(sub)
          continue
        endif
        children->add(sub.item)
        sources->extend(sub.sources)
        docs += sub.docs
        folders += sub.folders
      elseif this.Accepts(path)
        var doc: BI.BinderItem = BI.BinderItem.NewDocument(fnamemodify(path, ':t:r'), '')
        children->add(doc)
        sources[doc.id] = path
        docs += 1
      else
        this._Skip(path)
      endif
    endfor
    if docs == 0
      return {}
    endif
    var item: BI.BinderItem = BI.BinderItem.NewFolder(FolderName(dir))
    item.SetChildren(children)
    return {item: item, sources: sources, docs: docs, folders: folders}
  enddef

  # METHOD: Add the scanned tree of entry next to row, and copy the file
  # of every document in it.
  def _AddTree(row: T.Row, entry: dict<any>): BI.BinderItem
    var root: BI.BinderItem = entry.item
    MU.AddNear(this.project, row, root)
    var inserted: T.Row = T.FindRowById(T.Flatten(this.project), root.id)
    # The roles come before the paths: layout.vim puts chapter- in front
    # of the folder name of a chapter.
    this._SetRoles(root, inserted.ownerItem)
    LY.Place(this.project, root)
    this._WriteDocs(root, entry.sources)
    return root
  enddef

  # METHOD: Give item, and every folder in it, its role from its parent,
  # top down, where null_object means the top level.
  def _SetRoles(item: BI.BinderItem, parent: BI.BinderItem): void
    var role: string = this._RoleUnder(parent)
    # The rules of the Binder have the last word, in case the two ever
    # disagree. A refused role becomes a plain folder.
    item.SetRole(MU.RoleAllowedUnder(role, parent) ? role : CO.ROLE_NONE)
    for child in item.children
      if child.IsFolder()
        this._SetRoles(child, item)
      endif
    endfor
  enddef

  # METHOD: Return the role of an imported folder whose parent is parent:
  # Custom at the top level, Part under the Manuscript of a novel with
  # parts, Chapter under the Manuscript of a novel or under a Part, and no
  # role anywhere else, which includes the Manuscript of a short story or
  # a screenplay, where the documents are not grouped in chapters.
  def _RoleUnder(parent: BI.BinderItem): string
    if parent is null_object
      return CO.ROLE_CUSTOM
    endif
    if parent.structureRole ==# CO.ROLE_MANUSCRIPT
      if this.project.projectType ==# CO.TYPE_NOVEL_PARTS
        return CO.ROLE_PART
      endif
      return this.project.projectType ==# CO.TYPE_NOVEL ? CO.ROLE_CHAPTER : CO.ROLE_NONE
    endif
    if parent.structureRole ==# CO.ROLE_PART
      return CO.ROLE_CHAPTER
    endif
    return CO.ROLE_NONE
  enddef

  # METHOD: Copy the file of every document in item, in the order of the
  # tree, so that added holds them in that order.
  def _WriteDocs(item: BI.BinderItem, sources: dict<string>): void
    for child in item.children
      if child.IsFolder()
        this._WriteDocs(child, sources)
      else
        this._WriteCopy(sources[child.id], child)
        this.added->add(child)
      endif
    endfor
  enddef

  # METHOD: Add a document for path next to row, and copy path into its
  # file. Accepts has checked path.
  def _AddFile(row: T.Row, path: string): BI.BinderItem
    var doc: BI.BinderItem = BI.BinderItem.NewDocument(fnamemodify(path, ':t:r'), '')
    MU.AddNear(this.project, row, doc)
    # The file follows the place of the document in the tree, as for a new
    # document, so that Tidy Files has nothing to move after an import.
    LY.Place(this.project, doc)
    this._WriteCopy(path, doc)
    this.added->add(doc)
    return doc
  enddef

  # METHOD: Copy src into the file of doc, its folder first. Binary both
  # ways, so that the copy keeps the line endings of the source and its
  # last line as it is.
  def _WriteCopy(src: string, doc: BI.BinderItem): void
    var dst: string = doc.AbsPath(this.project.BinderRoot())
    mkdir(fnamemodify(dst, ':h'), 'p')
    writefile(readfile(src, 'b'), dst, 'b')
  enddef

  # METHOD: Return true when path is already in the binder folder of this
  # scrive, where an import would copy a document onto itself.
  def _Inside(path: string): bool
    return PA.Under(this.project.BinderRoot(), path)
  enddef
endclass
