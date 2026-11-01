vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# project.vim: one scrive, a Bartleby writing project: its Binder tree
# and the loading and saving of project.json. No UI, and no knowledge of
# where scrives are on disk, see scrive.vim.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/persist.vim' as PE
import autoload 'bartleby/log.vim' as L
import autoload 'bartleby/locale/binder.vim' as MB
import autoload 'bartleby/locale/common.vim' as MC
import autoload 'bartleby/path.vim' as PA
import 'bartleby/variables/constants.vim' as CO

const EXT_MD: string = '.md'

var log = L.New(expand('<sfile>:t'))



# FUNCTION: Return each scrive type, as stored in project.json, to its
# name in the message language. CO.TYPES gives the order.
export def TypeNames(): dict<string>
  return {
    [CO.TYPE_NOVEL]: MB.Novel(),
    [CO.TYPE_NOVEL_PARTS]: MB.NovelParts(),
    [CO.TYPE_SHORT_STORY]: MB.ShortStory(),
    [CO.TYPE_SCREENPLAY]: MC.Screenplay(),
  }
enddef

export class Project implements BI.ItemContainer
  # Absolute path of the .bartleby folder.
  var scriveDir: string
  var name: string = ''
  var projectType: string = CO.TYPE_NOVEL
  # The top-level binder items.
  var items: list<BI.BinderItem> = []
  # True once Load read project.json, or InitNew made a new scrive. Save
  # refuses before that, so that a project.json that failed to load is
  # never overwritten with an empty tree.
  var saveAllowed: bool = false
  # Why the last Load failed, empty after a good load.
  var loadError: string = ''

  def new(this.scriveDir)
  enddef

  # METHOD: Set the name and type of a new scrive, after construction and
  # before the first Save. A var field can be written only inside its
  # class, see Create in scrive.vim.
  def InitNew(newName: string, newType: string = CO.TYPE_NOVEL): void
    this.name = newName
    this.projectType = newType
    this.saveAllowed = true
  enddef

  # METHOD: Give a new, empty scrive its starter Binder tree. Called once,
  # after InitNew and before the first Save, for the same reason as InitNew.
  def SeedTree(newItems: list<BI.BinderItem>): void
    this.items = newItems
    this.EnsureTrash()
  enddef

  # METHOD: Add a top-level item, at the end but before the Trash, which
  # stays last. This and the next methods implement ItemContainer, see
  # binderitem.vim, for the top-level items, which have no owning folder.
  def AddChild(child: BI.BinderItem): void
    this.InsertChildAt(len(this.items), child)
  enddef

  # METHOD: Insert child at idx, but never after the Trash.
  def InsertChildAt(idx: number, child: BI.BinderItem): void
    var trashIdx: number = indexof(this.items, (_, item) => item.structureRole ==# CO.ROLE_TRASH)
    var at: number = trashIdx >= 0 && child.structureRole !=# CO.ROLE_TRASH
      ? min([idx, trashIdx]) : idx
    this.items->insert(child, at)
  enddef

  def RemoveChildAt(idx: number): void
    this.items->remove(idx)
  enddef

  def ChildAt(idx: number): BI.BinderItem
    return this.items[idx]
  enddef

  def ChildCount(): number
    return len(this.items)
  enddef

  def IdxOfChild(id: string): number
    for i in range(len(this.items))
      if this.items[i].id ==# id
        return i
      endif
    endfor
    return -1
  enddef

  def SwapChildren(i: number, j: number): void
    var tmp: BI.BinderItem = this.items[i]
    this.items[i] = this.items[j]
    this.items[j] = tmp
  enddef

  def BinderRoot(): string
    return this.scriveDir .. CO.PATH_BINDER
  enddef

  def ProjFilePath(): string
    return this.scriveDir .. '/' .. CO.PROJ_FILE
  enddef

  # METHOD: Return the document extension: .fountain for a screenplay, .md
  # for every other type.
  def DocExt(): string
    return this.projectType ==# CO.TYPE_SCREENPLAY ? CO.EXT_FOUNTAIN : EXT_MD
  enddef

  # METHOD: Read project.json. Returns false, and changes nothing, when the
  # file is missing, is not valid JSON, or does not hold a list of binder
  # items, as after a crash during a save. The error names the file.
  def Load(): bool
    var path: string = this.ProjFilePath()
    this.loadError = ''
    if !filereadable(path)
      return this.LoadFailed(MB.ProjJsonNot(this.scriveDir))
    endif
    var data: any
    var loadedItems: list<BI.BinderItem>
    try
      data = json_decode(join(readfile(path), "\n"))
      if type(data) != v:t_dict || type(get(data, 'items', null)) != v:t_list
          || indexof(data.items, (_, i) => type(i) != v:t_dict) >= 0
        return this.LoadFailed(MB.HoldsNoList(path))
      endif
      loadedItems = data.items->mapnew((_, i) => BI.BinderItem.FromDict(i))
    catch
      return this.LoadFailed(MB.CannotReadScrive(path, v:exception))
    endtry
    this.name = get(data, 'name', fnamemodify(this.scriveDir, ':t:r'))
    this.projectType = get(data, 'projectType', CO.TYPE_NOVEL)
    this.items = loadedItems
    this.EnsureTrash()
    this.saveAllowed = true
    return true
  enddef

  # METHOD: Record why Load failed, with the backup of project.json when
  # there is one, report it, and return false, for Load to return.
  def LoadFailed(reason: string): bool
    var backup: string = this.ProjFilePath() .. PE.BACKUP_SUFFIX
    this.loadError = reason .. (filereadable(backup)
      ? ' ' .. MB.VersionBeforeLast(backup) : '')
    log.Error(this.loadError)
    return false
  enddef

  # METHOD: Write project.json, and keep the version before as a backup.
  # Refuses, with an error, when this project was neither loaded nor made
  # new, see saveAllowed.
  def Save(): void
    if !this.saveAllowed
      log.Error(MB.NotSavedBecause(this.ProjFilePath()))
      return
    endif
    this.EnsureTrash()
    PE.WriteJson(this.ProjFilePath(), {
      name: this.name,
      projectType: this.projectType,
      items: this.items->mapnew((_, i) => i.ToDict()),
    }, true)
  enddef

  # METHOD: Return the Trash, the top level folder with ROLE_TRASH, or
  # null_object.
  def TrashFolder(): BI.BinderItem
    for item in this.items
      if item.structureRole ==# CO.ROLE_TRASH
        return item
      endif
    endfor
    return null_object
  enddef

  # METHOD: Make sure that the Trash exists and is the last folder at the
  # top level, whatever moved or was added after it. A scrive saved before
  # the Trash existed gets an empty one.
  def EnsureTrash(): void
    var trash: BI.BinderItem = this.TrashFolder()
    if trash is null_object
      trash = BI.BinderItem.NewFolder(MB.Trash(), CO.ROLE_TRASH)
    else
      this.items->filter((_, item) => item.id !=# trash.id)
    endif
    this.items->add(trash)
  enddef

  # METHOD: Find an item by id, depth first, or return null_object.
  def FindItem(id: string): BI.BinderItem
    def Walk(list: list<BI.BinderItem>): BI.BinderItem
      for item in list
        if item.id ==# id
          return item
        endif
        if item.IsFolder()
          var found: BI.BinderItem = Walk(item.children)
          if found isnot null_object
            return found
          endif
        endif
      endfor
      return null_object
    enddef
    return Walk(this.items)
  enddef

  # METHOD: Find a document by its absolute path, depth first. Return
  # null_object when the path is not a document of this scrive, as for a
  # buffer of another file.
  def FindItemByPath(path: string): BI.BinderItem
    var binderRoot: string = this.BinderRoot()
    def Walk(list: list<BI.BinderItem>): BI.BinderItem
      for item in list
        if item.IsDoc() && PA.Same(item.AbsPath(binderRoot), path)
          return item
        endif
        if item.IsFolder()
          var found: BI.BinderItem = Walk(item.children)
          if found isnot null_object
            return found
          endif
        endif
      endfor
      return null_object
    enddef
    return Walk(this.items)
  enddef
endclass
