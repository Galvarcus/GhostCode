vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# links.vim: links between the documents of a scrive. [[Mara]] links to the
# document titled Mara, and [[Mara|the captain]] links to it and reads the
# captain. [[Mara#Backstory]] links to the heading Backstory in it, and
# reads Mara. gf on a link opens the document, a rename offers to update
# the links to it, and compile shows each link as its text. In a
# screenplay, [[ ]] is a Fountain note, which gf follows and compile
# leaves out.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/binder.vim' as B
import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/dialog_popup.vim' as DP
import autoload 'bartleby/log.vim' as L
import autoload 'bartleby/picker.vim' as PI
import autoload 'bartleby/project.vim' as PO
import autoload 'bartleby/scrivenings.vim' as SV
import autoload 'bartleby/state.vim' as ST
import autoload 'bartleby/trash.vim' as TR
import autoload 'bartleby/tree.vim' as T
import autoload 'bartleby/wordcount.vim' as WC
import autoload 'bartleby/locale/binder.vim' as MB
import autoload 'bartleby/doctemplates.vim' as DT
import autoload 'bartleby/path.vim' as PA

# A link: [[target]] or [[target|text]]. A target holds no ] and no |, and
# a text holds no ].
const LINK_PAT: string = '\[\[\([^]|]\+\)\%(|\([^]]*\)\)\?\]\]'
# Between the folders of a path, in the list of documents with one title.
const CRUMB_SEP: string = ' / '
# The text before the cursor that opens a link, and the end of a link.
const LINK_OPEN_PAT: string = '\[\[$'
const LINK_CLOSE: string = ']]'
# The menu shows for one title too, and nothing is inserted until a title
# is picked. Vim inserts the first one at once otherwise.
const COMPLETE_OPTS: list<string> = ['menuone', 'noinsert']
# The highlight groups of good and broken links, which also name their
# text property types, and the groups they link to by default.
const HL_LINK: string = 'BartlebyLink'
const HL_LINK_BROKEN: string = 'BartlebyLinkBroken'
const HL_LINK_DEFAULT: string = 'Underlined'
const HL_LINK_BROKEN_DEFAULT: string = 'SpellBad'
# Between the title and the heading of a link, as in [[Mara#Backstory]].
const HEADING_SEP: string = '#'
# A Markdown heading of level 1 to 6, matching its text without the marks.
const HEADING_PAT: string = '^#\{1,6}\s\+\zs.\{-}\ze\%(\s\+#\+\)\=\s*$'
# The text before the cursor after [[Title#, with the title as group 1.
const HEADING_OPEN_PAT: string = '\[\[\([^]|#]\+\)#$'

var log = L.New(expand('<sfile>:t'))
var highlight_on: bool = g:bartleby_link_highlight
# The link targets and headings of each document file, by path, as
# {stamp, targets, headings}, so that a file is read again only when it
# changes. The stamp is the time and the size, because the time counts
# whole seconds. See DocInfo.
var doc_cache: dict<dict<any>> = {}

# FUNCTION: Return the link that covers byte column col of line, as {target,
# text}, or an empty dict. text is the target when the link has none of its
# own. col counts from 1, as col() does.
export def At(line: string, col: number): dict<string>
  var from: number = 0
  while true
    var found: list<any> = matchstrpos(line, LINK_PAT, from)
    if found[1] < 0 || found[1] >= col
      return {}
    endif
    if col <= found[2]
      var parts: list<string> = matchlist(found[0], LINK_PAT)
      var target: string = trim(parts[1])
      return {target: target, text: parts[2] ==# '' ? target : parts[2]}
    endif
    from = found[2]
  endwhile
  return {}
enddef

# FUNCTION: Return lines with each link replaced by its text, for compile.
# A link without a text of its own reads as its title, without a heading.
export def Plain(lines: list<string>): list<string>
  var project: PO.Project = ST.Get()
  var sets: dict<dict<bool>> = TitleSets(project is null_object ? [] : Docs(project, false))
  return lines->mapnew((_, line) => substitute(line, LINK_PAT,
    (m: list<string>): string => m[2] ==# '' ? Split(trim(m[1]), sets)[0] : m[2], 'g'))
enddef

# FUNCTION: Return the titles of docs, exactly and in lowercase, as sets
# for Split and IsTitle.
def TitleSets(docs: list<BI.BinderItem>): dict<dict<bool>>
  var sets: dict<dict<bool>> = {exact: {}, lower: {}}
  for d in docs
    sets.exact[d.title] = true
    sets.lower[tolower(d.title)] = true
  endfor
  return sets
enddef

# FUNCTION: Return true when title is in sets, exactly or without case.
def IsTitle(sets: dict<dict<bool>>, title: string): bool
  return has_key(sets.exact, title) || has_key(sets.lower, tolower(title))
enddef

# FUNCTION: Split the target of a link into its title and its heading, the
# heading empty when it has none. A target that is a title whole, such as
# Chapter #3, has no heading. Otherwise the first # divides the two.
export def Split(target: string, sets: dict<dict<bool>>): list<string>
  var idx: number = stridx(target, HEADING_SEP)
  if idx < 0 || IsTitle(sets, target)
    return [target, '']
  endif
  return [trim(strpart(target, 0, idx)), trim(strpart(target, idx + 1))]
enddef

# FUNCTION: Return the texts of the Markdown headings in lines.
def Headings(lines: list<string>): list<string>
  return lines->copy()->filter((_, l) => l =~# HEADING_PAT)->mapnew((_, l) => matchstr(l, HEADING_PAT))
enddef

# FUNCTION: Return the index in texts of heading, exactly or else without
# case, or -1.
def HeadingIdx(texts: list<string>, heading: string): number
  var idx: number = index(texts, heading)
  return idx >= 0 ? idx : texts->indexof((_, t) => t ==? heading)
enddef

# FUNCTION: Return the index of the line of heading in lines, or -1.
def HeadingLine(lines: list<string>, heading: string): number
  return HeadingIdx(lines->mapnew((_, l) => l =~# HEADING_PAT ? matchstr(l, HEADING_PAT) : ''), heading)
enddef

# FUNCTION: Return the documents of project titled title, outside the Trash:
# the exact matches, or else the matches that ignore case.
export def Find(project: PO.Project, title: string): list<BI.BinderItem>
  return Match(Docs(project, false), title)
enddef

def Match(docs: list<BI.BinderItem>, title: string): list<BI.BinderItem>
  var exact: list<BI.BinderItem> = docs->copy()->filter((_, d) => d.title ==# title)
  return !empty(exact) ? exact : docs->copy()->filter((_, d) => d.title ==? title)
enddef

# FUNCTION: Return the documents of project in tree order: those in the
# Trash, or those outside it.
def Docs(project: PO.Project, inTrash: bool): list<BI.BinderItem>
  return T.Flatten(project)->filter((_, r) => r.item.IsDoc() && TR.RowInTrash(r) == inTrash)
    ->mapnew((_, r) => r.item)
enddef

# FUNCTION: Return the path of each document of project, by id: the titles
# of its folders and its own, which tell documents with one title apart.
def Paths(project: PO.Project): dict<string>
  var titles: list<string> = []
  var paths: dict<string> = {}
  for r in T.Flatten(project)
    titles = slice(titles, 0, r.depth) + [r.item.title]
    if r.item.IsDoc()
      paths[r.item.id] = join(titles, CRUMB_SEP)
    endif
  endfor
  return paths
enddef

# FUNCTION: Return the folders of each document of project, by id, as
# Paths does without the title. A document at the top has none.
export def Folders(project: PO.Project): dict<string>
  var titles: list<string> = []
  var folders: dict<string> = {}
  for r in T.Flatten(project)
    if r.item.IsDoc()
      folders[r.item.id] = join(slice(titles, 0, r.depth), CRUMB_SEP)
    endif
    titles = slice(titles, 0, r.depth) + [r.item.title]
  endfor
  return folders
enddef

# FUNCTION: Return the targets of the links in lines.
def Targets(lines: list<string>): list<string>
  var targets: list<string> = []
  for line in lines
    var from: number = 0
    while true
      var found: list<any> = matchstrpos(line, LINK_PAT, from)
      if found[1] < 0
        break
      endif
      targets->add(trim(matchlist(found[0], LINK_PAT)[1]))
      from = found[2]
    endwhile
  endfor
  return targets
enddef

# FUNCTION: Return the link targets and the headings of doc, as {targets,
# headings}: from its buffer when loaded, so that unsaved text counts,
# else from its file, through the cache. root is the binder root with
# symlinks resolved, as the keys of loaded are, so that no path is
# resolved one at a time.
def DocInfo(root: string, doc: BI.BinderItem, loaded: dict<number>): dict<any>
  var path: string = doc.AbsPath(root)
  var bufNr: number = WC.LoadedBuf(loaded, path)
  if bufNr > 0
    var lines: list<string> = getbufline(bufNr, 1, '$')
    return {targets: Targets(lines), headings: Headings(lines)}
  endif
  var time: number = getftime(path)
  if time < 0
    return {targets: [], headings: []}
  endif
  var stamp: string = $'{time} {getfsize(path)}'
  var cached: dict<any> = get(doc_cache, path, {})
  if get(cached, 'stamp', '') !=# stamp
    var lines: list<string> = readfile(path)
    cached = {stamp: stamp, targets: Targets(lines), headings: Headings(lines)}
    doc_cache[path] = cached
  endif
  return cached
enddef

# FUNCTION: Return the documents outside the Trash, in tree order, that
# link to item, without item itself. A link counts as gf finds it: by the
# exact title, or else without case, with a heading or not. A document in
# the Trash has none.
export def LinkedFrom(project: PO.Project, item: BI.BinderItem): list<BI.BinderItem>
  var docs: list<BI.BinderItem> = Docs(project, false)
  if docs->indexof((_, d) => d.id ==# item.id) < 0
    return []
  endif
  var sets: dict<dict<bool>> = TitleSets(docs)
  var LinksHere = (t: string): bool => {
    var title: string = Split(t, sets)[0]
    return title ==# item.title || (!has_key(sets.exact, title) && title ==? item.title)
  }
  var loaded: dict<number> = WC.LoadedBufs()
  var root: string = resolve(project.BinderRoot())
  return docs->filter((_, d) => d.id !=# item.id
    && DocInfo(root, d, loaded).targets->indexof((_, t) => LinksHere(t)) >= 0)
enddef

# FUNCTION: Define the highlight groups of the links, unless a color
# scheme or the user did. A default link outlives :colorscheme.
def DefineHighlights(): void
  execute $'highlight default link {HL_LINK} {HL_LINK_DEFAULT}'
  execute $'highlight default link {HL_LINK_BROKEN} {HL_LINK_BROKEN_DEFAULT}'
enddef

# FUNCTION: Mark each link in buffer bufNr as good or broken, with text
# properties, which keep the syntax colors below and follow edits. A link
# is good when gf finds a document outside the Trash, and its heading in
# it when it names one. Only the link types are replaced, so the title
# lines of a Scrivening keep theirs.
export def Highlight(project: PO.Project, bufNr: number): void
  if !highlight_on
    return
  endif
  if empty(prop_type_get(HL_LINK))
    DefineHighlights()
    prop_type_add(HL_LINK, {highlight: HL_LINK})
    prop_type_add(HL_LINK_BROKEN, {highlight: HL_LINK_BROKEN})
  endif
  prop_remove({types: [HL_LINK, HL_LINK_BROKEN], bufnr: bufNr, all: true})
  var docs: list<BI.BinderItem> = Docs(project, false)
  var sets: dict<dict<bool>> = TitleSets(docs)
  var loaded: dict<number> = WC.LoadedBufs()
  var root: string = resolve(project.BinderRoot())
  # One search of the whole buffer, and one call per type to add the
  # properties: a loop over lines took 34 ms for 2,000 links.
  var spans: dict<list<any>> = {[HL_LINK]: [], [HL_LINK_BROKEN]: []}
  for m in matchbufline(bufNr, LINK_PAT, 1, '$', {submatches: true})
    var [title, heading] = Split(trim(m.submatches[0]), sets)
    var good: bool = IsTitle(sets, title) && (heading ==# ''
      || Match(docs, title)->indexof((_, d) => HeadingIdx(DocInfo(root, d, loaded).headings, heading) >= 0) >= 0)
    var col: number = m.byteidx + 1
    spans[good ? HL_LINK : HL_LINK_BROKEN]->add([m.lnum, col, m.lnum, col + len(m.text)])
  endfor
  for [type, list] in items(spans)
    if !empty(list)
      prop_add_list({type: type, bufnr: bufNr}, list)
    endif
  endfor
enddef

# FUNCTION: Highlight the links again in each window of documents, after a
# change of titles that no edit of theirs shows, such as a rename.
export def RefreshWindows(project: PO.Project): void
  for bufNr in tabpagebuflist()->sort()->uniq()
    if getbufvar(bufNr, 'bartleby_link_doc', false)
      Highlight(project, bufNr)
    endif
  endfor
enddef

# FUNCTION: After [[ in insert mode, offer the titles of the documents
# outside the Trash, in tree order, each with its folders. A title ends
# the link, unless ]] already follows the cursor.
export def CompleteTitles(): void
  var col: number = col('.')
  var line: string = getline('.')
  var project: PO.Project = ST.Get()
  if project is null_object || strpart(line, 0, col - 1) !~# LINK_OPEN_PAT
    return
  endif
  var close: string = strpart(line, col - 1, len(LINK_CLOSE)) ==# LINK_CLOSE ? '' : LINK_CLOSE
  var folders: dict<string> = Folders(project)
  # dup keeps documents that share a title, which Vim would show once.
  var items: list<dict<any>> = Docs(project, false)->mapnew((_, d) => ({
    word: d.title .. close,
    abbr: d.title,
    menu: folders[d.id],
    dup: 1,
  }))
  if empty(items)
    return
  endif
  SetCompleteOpts()
  complete(col, items)
enddef

# FUNCTION: After [[Title# in insert mode, offer the headings of the
# documents titled Title, each with its folders when several share the
# title. A heading ends the link, unless ]] already follows the cursor.
export def CompleteHeadings(): void
  var col: number = col('.')
  var line: string = getline('.')
  var project: PO.Project = ST.Get()
  var title: string = trim(get(matchlist(strpart(line, 0, col - 1), HEADING_OPEN_PAT), 1, ''))
  if project is null_object || title ==# ''
    return
  endif
  var docs: list<BI.BinderItem> = Find(project, title)
  var close: string = strpart(line, col - 1, len(LINK_CLOSE)) ==# LINK_CLOSE ? '' : LINK_CLOSE
  var folders: dict<string> = Folders(project)
  var loaded: dict<number> = WC.LoadedBufs()
  var root: string = resolve(project.BinderRoot())
  var items: list<dict<any>> = []
  for d in docs
    for h in DocInfo(root, d, loaded).headings
      items->add({word: h .. close, abbr: h, menu: len(docs) > 1 ? folders[d.id] : '', dup: 1})
    endfor
  endfor
  if empty(items)
    return
  endif
  SetCompleteOpts()
  complete(col, items)
enddef

# FUNCTION: Set the options of the title menu for this buffer, and restore
# the user's own when the menu closes.
def SetCompleteOpts(): void
  b:bartleby_link_completeopt = &l:completeopt
  &l:completeopt = (split(&completeopt, ',') + COMPLETE_OPTS)->sort()->uniq()->join(',')
  augroup bartleby_link_complete
    autocmd! * <buffer>
    autocmd CompleteDone <buffer> ++once RestoreCompleteOpts()
  augroup END
enddef

def RestoreCompleteOpts(): void
  &l:completeopt = b:bartleby_link_completeopt
  unlet b:bartleby_link_completeopt
enddef

# FUNCTION: Open the document of the link under the cursor. Off a link, or
# with no scrive open, do what gf does without Bartleby.
export def Follow(): void
  var link: dict<string> = At(getline('.'), col('.'))
  var project: PO.Project = ST.Get()
  if empty(link) || project is null_object
    try
      normal! gf
    catch
      echohl ErrorMsg
      echomsg substitute(v:exception, '^Vim(normal):', '', '')
      echohl None
    endtry
    return
  endif
  var [title, heading] = Split(link.target, TitleSets(Docs(project, false)))
  var found: list<BI.BinderItem> = Find(project, title)
  if len(found) ==# 1
    OpenAt(project, found[0], heading)
  elseif len(found) > 1
    PI.PickOne(MB.PickLinked(title), found->mapnew((_, d) => d.id), (id: string) => {
      OpenAt(project, project.FindItem(id), heading)
    }, '', Paths(project))
  elseif !empty(Match(Docs(project, true), title))
    log.Info(MB.LinkInTrash(title))
  else
    OfferToCreate(project, title)
  endif
enddef

# FUNCTION: Open doc, at heading when one is given. In a Scrivening the
# heading is looked for in the text of its section, unsaved edits
# included. A missing heading leaves the cursor at the top, with a
# message.
def OpenAt(project: PO.Project, doc: BI.BinderItem, heading: string): void
  B.OpenDoc(project, doc)
  if heading ==# ''
    return
  endif
  var path: string = doc.AbsPath(project.BinderRoot())
  var inScrivening: bool = SV.IsScrivening(bufnr())
  if !inScrivening && !PA.Same(expand('%:p'), path)
    return
  endif
  var lines: list<string> = inScrivening ? get(SV.SectionTexts(), path, []) : getline(1, '$')
  var idx: number = HeadingLine(lines, heading)
  if idx < 0
    log.Info(MB.NoHeading(doc.title, heading))
    idx = 0
  endif
  if inScrivening
    SV.ShowDoc(doc.id, idx)
  else
    cursor(idx + 1, 1)
  endif
enddef

# FUNCTION: Offer to create a document titled title next to the document
# of the current buffer, with the first template there, and open it. A
# link outside the documents of the scrive has no place for one.
def OfferToCreate(project: PO.Project, title: string): void
  var here: BI.BinderItem = SV.DocHere(project)
  if here is null_object
    log.Info(MB.NoLinked(title))
    return
  endif
  DP.Confirm(MB.CreateLinked(title), () => {
    var row: T.Row = T.FindRowById(T.Flatten(project), here.id)
    if row isnot null_object
      B.OpenDoc(project, B.AddDocNear(project, row, title, DT.FirstLines(project, row, title)))
    endif
  }, true)
enddef

# FUNCTION: Return lines with each link to oldTitle pointing to newTitle, and
# the number of links that changed. A link keeps the text that it shows, so
# a rename does not change the compiled text: [[Mara]] becomes
# [[Mara Jones|Mara]], and [[Mara#Backstory]] becomes
# [[Mara Jones#Backstory|Mara]]. A target matches oldTitle when it differs
# only in case, as when the link is followed. sets, from TitleSets, keep a
# title with # whole. The renamed document is no longer in them, so a
# target that is oldTitle whole is matched first.
export def Retitle(lines: list<string>, oldTitle: string, newTitle: string,
    sets: dict<dict<bool>> = {exact: {}, lower: {}}): list<any>
  var count: number = 0
  var out: list<string> = lines->mapnew((_, line) => substitute(line, LINK_PAT,
    (m: list<string>): string => {
      var target: string = trim(m[1])
      var [title, heading] = target ==? oldTitle ? [target, ''] : Split(target, sets)
      if title !=? oldTitle
        return m[0]
      endif
      count += 1
      var dest: string = heading ==# '' ? newTitle : $'{newTitle}{HEADING_SEP}{heading}'
      var text: string = m[2] ==# '' ? title : m[2]
      return text ==# newTitle ? $'[[{dest}]]' : $'[[{dest}|{text}]]'
    }, 'g'))
  return [out, count]
enddef

# FUNCTION: Count the links to oldTitle in the documents of project, and with
# write, point them at newTitle. Return the count. An open buffer of a
# document changes in place, with its own undo, and a closed one changes on
# disk. An open Scrivening is saved first and built again after, so that it
# neither loses the change nor writes its old text over it.
export def Retarget(project: PO.Project, oldTitle: string, newTitle: string, write: bool = true): number
  if write
    SV.SaveIfModified()
  endif
  var loaded: dict<number> = WC.LoadedBufs()
  var sets: dict<dict<bool>> = TitleSets(Docs(project, false))
  var total: number = 0
  for doc in Docs(project, false) + Docs(project, true)
    var path: string = doc.AbsPath(project.BinderRoot())
    var bufNr: number = WC.LoadedBuf(loaded, path)
    var lines: list<string> = bufNr > 0 ? getbufline(bufNr, 1, '$')
      : (filereadable(path) ? readfile(path) : [])
    var [out, count] = Retitle(lines, oldTitle, newTitle, sets)
    if count ==# 0
      continue
    endif
    total += count
    if !write
      continue
    endif
    if bufNr > 0
      for i in range(len(lines))
        if lines[i] !=# out[i]
          setbufline(bufNr, i + 1, out[i])
        endif
      endfor
    else
      writefile(out, path)
    endif
  endfor
  if write && total > 0
    SV.SyncWithTree(project, true)
  endif
  return total
enddef

# FUNCTION: After a document was renamed from oldTitle, offer to point the
# links to it at newTitle. Not while another document still has oldTitle,
# which the links then lead to.
export def OfferRetarget(project: PO.Project, oldTitle: string, newTitle: string): void
  if !empty(Find(project, oldTitle))
    return
  endif
  var count: number = Retarget(project, oldTitle, newTitle, false)
  if count ==# 0
    return
  endif
  DP.Confirm(MB.UpdateLinks(count), () => {
    log.Info(MB.LinksUpdated(Retarget(project, oldTitle, newTitle)))
    RefreshWindows(project)
  }, true)
enddef
