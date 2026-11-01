vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# scrive.vim: finds, opens, and creates scrives, the Bartleby writing
# projects, under g:bartleby_binder_root. The Binder tree is in
# project.vim and the UI in binder.vim.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/project.vim' as PO
import autoload 'bartleby/templates.vim' as TE
import autoload 'bartleby/import.vim' as IM
import autoload 'bartleby/mutate.vim' as MU
import autoload 'bartleby/tree.vim' as T
import autoload 'bartleby/log.vim' as L
import autoload 'bartleby/locale/binder.vim' as MB
import autoload 'bartleby/locale/common.vim' as MC
import 'bartleby/variables/constants.vim' as CO

var log = L.New(expand('<sfile>:t'))
var binder_root: string = g:bartleby_binder_root


# FUNCTION: Return the folder that holds the scrives: a Bartleby folder
# in g:bartleby_binder_root when it is set, else in ~/Documents. The
# default is ~/Documents/Bartleby.
export def BinderRoot(): string
  var normalized: string = substitute(fnamemodify(binder_root, ':p'), '[/\\]$', '', '')
  return normalized .. '/' .. CO.SCRIVE_FOLDER
enddef

export def ScrivePath(name: string): string
  return BinderRoot() .. '/' .. name .. CO.SCRIVE_EXT
enddef

# FUNCTION: Return the bare name of every .bartleby folder directly in
# the binder root.
export def ListScrives(): list<string>
  var root: string = BinderRoot()
  if !isdirectory(root)
    return []
  endif
  # nosuf true, so that a wildignore of the writer cannot hide a scrive.
  return globpath(root, '*' .. CO.SCRIVE_EXT, true, true)
    ->filter((_, p) => isdirectory(p))
    ->mapnew((_, p) => fnamemodify(p, ':t:r'))
enddef

# FUNCTION: Complete scrive names for :BartlebyOpen, the customlist
# function of the command. Vim passes only the last word before the
# cursor as argLead and replaces only that word, but a name can contain
# spaces. So the whole argument is read from cmdLine, see MatchNames.
export def CompleteNames(argLead: string, cmdLine: string, cursorPos: number): list<string>
  var typed: string = matchstr(strpart(cmdLine, 0, cursorPos), '^\s*\S\+\s\+\zs.*$')
  return MatchNames(ListScrives(), typed, argLead)
enddef

# FUNCTION: Return the names that match typed, the whole argument so far,
# as the text that replaces argLead, its last word. Matching ignores case.
# With fuzzy in wildoptions, it is fuzzy, as in Vim's own completion.
export def MatchNames(names: list<string>, typed: string, argLead: string): list<string>
  var matches: list<string> = &wildoptions =~# 'fuzzy' && typed !=# ''
    ? matchfuzzy(names, typed)
    : names->copy()->filter((_, n) => stridx(tolower(n), tolower(typed)) == 0)->sort('i')
  # The words before argLead are already on the command line. Keep only
  # names that start with them, and return the rest of each name.
  var done: string = strpart(typed, 0, strlen(typed) - strlen(argLead))
  return matches
    ->filter((_, n) => stridx(tolower(n), tolower(done)) == 0)
    ->mapnew((_, n) => strpart(n, strlen(done)))
enddef

# FUNCTION: Return name, or the one scrive name that differs from it only
# in case when no scrive has name exactly. Tab completion replaces only
# the last word, so a completed name can keep a first word in the case
# that was typed, as in my Novel for My Novel.
export def ResolveName(name: string): string
  # The folders themselves, not isdirectory, which answers for another
  # case on a file system that folds it, as macOS and Windows do: it said
  # yes for my novel and the name of the scrive, My Novel, was lost.
  # REFERENCE: https://github.com/Galvarcus/bartleby/issues/50
  var scrives: list<string> = ListScrives()
  if index(scrives, name) >= 0
    return name
  endif
  var matches: list<string> = scrives->copy()->filter((_, n) => n ==? name)
  return len(matches) == 1 ? matches[0] : name
enddef

# FUNCTION: Load a scrive by name, or return null_object when its folder
# or project.json is missing or cannot be read. A name that differs from
# one scrive only in case opens that scrive, see ResolveName.
export def Open(name: string): PO.Project
  var dir: string = ScrivePath(ResolveName(name))
  if !isdirectory(dir)
    log.Error(MC.NoScriveNamed(name, BinderRoot()))
    return null_object
  endif
  var project: PO.Project = PO.Project.new(dir)
  if !project.Load()
    return null_object
  endif
  return project
enddef

# FUNCTION: Create a scrive on disk: the binder folder, a project.json
# with the starter tree of DefaultTree for projectType, and the empty
# files of that tree. Without withStarters, the Manuscript folder starts
# empty, for a scrive that an import fills, see CreateFrom. Return it
# loaded.
export def Create(name: string, projectType: string = CO.TYPE_NOVEL,
    withStarters: bool = true): PO.Project
  var dir: string = ScrivePath(name)
  if isdirectory(dir)
    log.Error(MB.ScriveAlreadyExists(name, dir))
    return null_object
  endif
  mkdir(dir .. CO.PATH_BINDER, 'p')
  var project: PO.Project = PO.Project.new(dir)
  project.InitNew(name, projectType)
  var tree: list<BI.BinderItem> = TE.DefaultTree(projectType, project.DocExt())
  if !withStarters
    for folder in tree
      if folder.structureRole ==# CO.ROLE_MANUSCRIPT
        folder.SetChildren([])
      endif
    endfor
  endif
  TE.Materialize(tree, project.BinderRoot())
  project.SeedTree(tree)
  project.Save()
  return project
enddef

# FUNCTION: Create a scrive named name, of projectType, from src, a file
# or a folder: the scrive has no starter documents, and the import fills
# its Manuscript folder, see import.vim. A folder that holds the export of
# a project of another writing application fills every folder of the
# scrive instead, and then the Manuscript row below is not used, because
# the import knows where each part of the export belongs. Return the
# importer, which holds the project and what came in. Return null_object,
# and leave nothing behind, when the scrive cannot be made, or when src
# holds no document that the scrive type takes: the folder of a scrive
# with neither starters nor an import would be worse than none.
export def CreateFrom(name: string, projectType: string, src: string): IM.Importer
  var project: PO.Project = Create(name, projectType, false)
  if project is null_object
    return null_object
  endif
  var importer: IM.Importer = IM.Importer.new(project)
  importer.Plan([src])
  var manuscript: BI.BinderItem = MU.FindManuscript(project)
  importer.Apply(manuscript is null_object
    ? null_object
    : T.FindRowById(T.Flatten(project), manuscript.id))
  if empty(importer.added)
    # The report goes out here, because the scrive that would carry it is
    # about to go: it names every source that was left and tells the writer
    # to export a format that Bartleby cannot read again as text.
    if !empty(importer.skipped)
      log.Warn(importer.Report())
    endif
    # The folder was made by the Create above, so nothing of the user is
    # in it.
    delete(project.scriveDir, 'rf')
    return null_object
  endif
  project.Save()
  return importer
enddef
