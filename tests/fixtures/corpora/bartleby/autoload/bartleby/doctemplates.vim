vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# doctemplates.vim: templates for new documents, such as a character sheet.
# A template is a file in a folder named by the role of the Binder folder
# that it is for, such as templates/characters/character-sheet.md, with the
# extension of the documents of a scrive, .md or .fountain. Bartleby has its
# own, and g:bartleby_doc_templates_dir has yours, which add to them or
# replace one of the same name. {{title}}, {{date}}, {{author}}, and
# {{scrive}} are filled in, and {{t:text}} becomes text in the language of
# the messages, see tools/i18n/extract.py.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/i18n.vim' as IN
import autoload 'bartleby/profile.vim' as PR
import autoload 'bartleby/project.vim' as PO
import autoload 'bartleby/tree.vim' as T
import 'bartleby/variables/constants.vim' as CO

const BUILTIN_DIR: string = expand('<sfile>:p:h:h:h') .. '/templates'
# Between the words of a file name, such as character-sheet.
const SEP_PAT: string = '[-_]'
const VAR_PAT: string = '{{\(\w\+\)}}'
const TEXT_PAT: string = '{{t:\([^}]\+\)}}'
const DATE_FMT: string = '%Y-%m-%d'

var user_dir: string = g:bartleby_doc_templates_dir

# FUNCTION: Return the name of a template in the picker, from the name of
# its file without the extension, translated: character-sheet becomes
# Character sheet. tools/i18n/extract.py makes the same name.
export def Label(stem: string): string
  var text: string = substitute(stem, SEP_PAT, ' ', 'g')
  return IN.TFile(toupper(text[0]) .. text[1 :])
enddef

def Dirs(): list<string>
  return [BUILTIN_DIR] + (user_dir ==# '' ? [] : [fnamemodify(user_dir, ':p')])
enddef

# FUNCTION: Return the templates of role for documents with ext, as
# [{name, path}], sorted by file name. A template in a later folder of dirs
# replaces one of the same file name.
export def List(role: string, ext: string, dirs: list<string> = Dirs()): list<dict<string>>
  var found: dict<string> = {}
  for dir in dirs
    for path in glob($'{dir}/{role}/*{ext}', true, true)
      found[fnamemodify(path, ':t:r')] = path
    endfor
  endfor
  return sort(keys(found))->mapnew((_, stem) => ({name: Label(stem), path: found[stem]}))
enddef

# FUNCTION: Return the templates for a document added next to row, from
# dirs: those of the nearest folder around it whose role has any, so that a
# chapter without templates falls back to the Manuscript. As in AddNear of
# mutate.vim, a document goes into row when row is a folder.
export def ForRow(project: PO.Project, row: T.Row, dirs: list<string> = Dirs()): list<dict<string>>
  if row is null_object
    return []
  endif
  var rows: list<T.Row> = T.Flatten(project)
  var i: number = T.IdxOfRowById(rows, row.item.id)
  var depth: number = row.item.IsFolder() ? row.depth + 1 : row.depth
  while i >= 0
    var r: T.Row = rows[i]
    if r.depth < depth
      depth = r.depth
      if r.item.IsFolder() && r.item.structureRole !=# CO.ROLE_NONE
        var found: list<dict<string>> = List(r.item.structureRole, project.DocExt(), dirs)
        if !empty(found)
          return found
        endif
      endif
    endif
    i -= 1
  endwhile
  return []
enddef

# FUNCTION: Return lines with their placeholders filled in from vars, and
# {{t:text}} translated. A placeholder that vars lacks stays as it is.
export def Fill(lines: list<string>, vars: dict<string>): list<string>
  return lines->mapnew((_, line) => line
    ->substitute(TEXT_PAT, (m: list<string>): string => IN.TFile(m[1]), 'g')
    ->substitute(VAR_PAT, (m: list<string>): string => get(vars, m[1], m[0]), 'g'))
enddef

# FUNCTION: Return the lines of the template at path, filled in for a
# document titled title in project.
export def Lines(path: string, project: PO.Project, title: string): list<string>
  return Fill(readfile(path), {
    title: title,
    date: strftime(DATE_FMT),
    author: PR.Resolve(project).EffectiveAuthor(),
    scrive: project.name,
  })
enddef

# FUNCTION: Return the lines of the first template for a document added
# next to row, filled in, or none, for a document made without asking.
export def FirstLines(project: PO.Project, row: T.Row, title: string): list<string>
  var found: list<dict<string>> = ForRow(project, row)
  return empty(found) ? [] : Lines(found[0].path, project, title)
enddef
