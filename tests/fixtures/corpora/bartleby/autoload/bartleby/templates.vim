vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# templates.vim: the starter Binder tree for each scrive type, and the
# folders and documents on disk behind it. Used once, when a scrive is
# created, see Create in scrive.vim.
#
# In a Novel or a Novel with Parts, a chapter is a folder of scenes, not
# one file, so its compiled heading comes from the folder title, never
# from file content, see ConcatenateManuscript in compile.vim. Every
# starter folder has a structureRole, so that the Binder shows Chapter
# and Part prefixes and folders move only where their role allows.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/layout.vim' as LY
import autoload 'bartleby/locale/binder.vim' as MB
import autoload 'bartleby/locale/common.vim' as MC
import 'bartleby/variables/constants.vim' as CO

# FUNCTION: Return the title of the first scene of a chapter, in the
# message language. mutate.vim uses it too, for a new chapter.
export def FirstSceneTitle(): string
  return MB.Scene()
enddef

# FUNCTION: Return a chapter folder with one starter scene. DefaultTree
# gives the scene its path, see layout.vim.
def ChapterWithScene(chapterNum: string): BI.BinderItem
  var chapter: BI.BinderItem = BI.BinderItem.NewFolder(chapterNum, CO.ROLE_CHAPTER)
  chapter.SetChildren([BI.BinderItem.NewDocument(FirstSceneTitle(), '')])
  return chapter
enddef

# FUNCTION: Return a folder with one starter document, for types that are
# a single flat file, such as the draft of a Short Story or the scenes of
# a Screenplay.
def FolderWithDoc(folderTitle: string, docTitle: string, role: string = CO.ROLE_NONE): BI.BinderItem
  var folder: BI.BinderItem = BI.BinderItem.NewFolder(folderTitle, role)
  folder.SetChildren([BI.BinderItem.NewDocument(docTitle, '')])
  return folder
enddef

# FUNCTION: Return the Front Matter folder. It starts empty. Add a
# dedication, acknowledgments, and similar pages as documents.
def FrontMatterFolder(): BI.BinderItem
  return BI.BinderItem.NewFolder(MB.FrontMatter(), CO.ROLE_FRONT_MATTER)
enddef

# FUNCTION: Return the Back Matter folder. It starts empty, like Front
# Matter, for pages such as an appendix or an author's note.
def BackMatterFolder(): BI.BinderItem
  return BI.BinderItem.NewFolder(MB.BackMatter(), CO.ROLE_BACK_MATTER)
enddef

# FUNCTION: Return the Characters folder. It starts empty, for character
# sheets and notes that are never compiled.
def CharsFolder(): BI.BinderItem
  return BI.BinderItem.NewFolder(MB.Chars(), CO.ROLE_CHARS)
enddef

# FUNCTION: Return the Research folder. It starts empty, for places, notes,
# and anything else that you collect, which are never compiled.
def ResearchFolder(): BI.BinderItem
  return BI.BinderItem.NewFolder(MB.Research(), CO.ROLE_RESEARCH)
enddef

# FUNCTION: Return the five structural folders around manuscript, in order.
# A novel and a short story start with them. A screenplay has no Back Matter.
def StandardTree(manuscript: BI.BinderItem): list<BI.BinderItem>
  return [FrontMatterFolder(), manuscript, BackMatterFolder(), CharsFolder(), ResearchFolder()]
enddef

export def DefaultTree(projectType: string, docExt: string): list<BI.BinderItem>
  var tree: list<BI.BinderItem> = []
  if projectType ==# CO.TYPE_NOVEL
    var manuscript: BI.BinderItem = BI.BinderItem.NewFolder(MC.Manuscript(), CO.ROLE_MANUSCRIPT)
    manuscript.SetChildren([ChapterWithScene('1')])
    tree = StandardTree(manuscript)
  elseif projectType ==# CO.TYPE_NOVEL_PARTS
    var part1: BI.BinderItem = BI.BinderItem.NewFolder('1', CO.ROLE_PART)
    part1.SetChildren([ChapterWithScene('1')])
    var part2: BI.BinderItem = BI.BinderItem.NewFolder('2', CO.ROLE_PART)
    var manuscript: BI.BinderItem = BI.BinderItem.NewFolder(MC.Manuscript(), CO.ROLE_MANUSCRIPT)
    manuscript.SetChildren([part1, part2])
    tree = StandardTree(manuscript)
  elseif projectType ==# CO.TYPE_SHORT_STORY
    tree = StandardTree(FolderWithDoc(MC.Manuscript(), MB.Draft(), CO.ROLE_MANUSCRIPT))
  elseif projectType ==# CO.TYPE_SCREENPLAY
    # A screenplay has no Back Matter, so it is the one type that does not use
    # StandardTree.
    tree = [
      FrontMatterFolder(),
      FolderWithDoc(MC.Screenplay(), FirstSceneTitle(), CO.ROLE_MANUSCRIPT),
      CharsFolder(),
      ResearchFolder(),
    ]
  else
    return tree
  endif
  # The paths of the starter documents follow the layout, see layout.vim.
  LY.AssignPaths(tree, docExt)
  return tree
enddef

# FUNCTION: Create an empty file for every document in items, and its
# folder first, so that the tree from DefaultTree exists on disk. The
# Binder cannot open a document that does not exist.
export def Materialize(items: list<BI.BinderItem>, binderRoot: string): void
  for item in items
    if item.IsFolder()
      Materialize(item.children, binderRoot)
    else
      var path: string = item.AbsPath(binderRoot)
      if !filereadable(path)
        mkdir(fnamemodify(path, ':h'), 'p')
        writefile([], path)
      endif
    endif
  endfor
enddef
