vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# search.vim: searches the text of all documents of a scrive into the
# quickfix list with :vimgrep. The only UI is the query prompt: browse
# the results with Vim's quickfix commands, such as :copen, :cnext, and
# :cprev.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/project.vim' as PO
import autoload 'bartleby/inputpopup.vim' as IP
import autoload 'bartleby/log.vim' as L
import autoload 'bartleby/tree.vim' as T
import autoload 'bartleby/trash.vim' as TR
import autoload 'bartleby/locale/views.vim' as MV

var log = L.New(expand('<sfile>:t'))

export def Run(project: PO.Project): void
  IP.PromptText(MV.SearchScrive(), '', (query: string) => {
    RunSearch(project, query)
  })
enddef

# FUNCTION: Return the files that a search reads: the documents of the
# Binder that are on disk, without those in the Trash.
export def SearchFiles(project: PO.Project): list<string>
  var trashed: dict<bool> = TR.IdsInTrash(project)
  return T.Flatten(project)
    ->filter((_, row) => row.item.IsDoc() && !has_key(trashed, row.item.id))
    ->mapnew((_, row) => row.item.AbsPath(project.BinderRoot()))
    ->filter((_, path) => filereadable(path))
enddef

def RunSearch(project: PO.Project, query: string): void
  if query ==# ''
    return
  endif

  var files: list<string> = SearchFiles(project)
  if empty(files)
    log.Info(MV.NoDocsSearch())
    return
  endif

  # Very nomagic: search for the plain text, not a regex, which is what a
  # find in project prompt usually means. With very nomagic, only the
  # backslash and the pattern delimiter need escaping.
  var pattern: string = '\V' .. escape(query, '/\')
  var fileArgs: string = join(files->mapnew((_, f) => fnameescape(f)), ' ')
  execute $'silent! vimgrep /{pattern}/j {fileArgs}'

  if empty(getqflist())
    log.Info(MV.NoMatches(query))
    return
  endif
  copen
enddef
