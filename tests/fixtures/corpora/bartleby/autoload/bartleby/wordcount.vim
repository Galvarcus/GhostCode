vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# wordcount.vim: counts the words of documents and folders, for the
# Outliner and the writing goals. A word is a run of characters between
# white space.
#
# A document open in a buffer, or in a Scrivening, is counted from it, so
# that text not yet saved counts, and the title lines of a Scrivening do
# not. Any other document is counted from its file, and the
# count is kept until the size or the time of the file changes, so that an
# unchanged file is read once. Totals counts each document once, and adds
# the counts up into the totals of the folders.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/scrivenings.vim' as SV
import autoload 'bartleby/path.vim' as PA

# The words of each file read: path to size, time, and count.
var cache: dict<list<number>> = {}

# FUNCTION: Return the number of words in lines.
export def Count(lines: list<string>): number
  return len(split(join(lines, ' ')))
enddef

# FUNCTION: Return the loaded buffers that have a file, by the one
# spelling of their path, see path.vim. Vim names a buffer by the resolved
# path, so that one under /tmp on macOS is under /private/tmp, and on
# Windows by the long name with backslashes, while AbsPath neither
# resolves nor turns a slash around. Look a path up with LoadedBuf.
export def LoadedBufs(): dict<number>
  var bufs: dict<number> = {}
  for info in getbufinfo({bufloaded: 1})
    if info.name !=# ''
      bufs[PA.Canon(info.name)] = info.bufnr
    endif
  endfor
  return bufs
enddef

# FUNCTION: Return the buffer of path in bufs, from LoadedBufs, or -1.
export def LoadedBuf(bufs: dict<number>, path: string): number
  return get(bufs, PA.Canon(path), -1)
enddef

# FUNCTION: Return the words of the document at path: from the open
# Scrivening when it holds it, from its buffer when it is loaded, or else
# from its file, through the cache. A missing file has no words.
def DocWords(path: string, bufs: dict<number>, sections: dict<list<string>>): number
  if has_key(sections, path)
    return Count(sections[path])
  endif
  var bufNr: number = LoadedBuf(bufs, path)
  if bufNr > 0
    return Count(getbufline(bufNr, 1, '$'))
  endif
  if !filereadable(path)
    return 0
  endif
  var stamp: list<number> = [getfsize(path), getftime(path)]
  var known: list<number> = get(cache, path, [])
  if !empty(known) && known[0 : 1] == stamp
    return known[2]
  endif
  var words: number = Count(readfile(path))
  cache[path] = stamp + [words]
  return words
enddef

# FUNCTION: Return the words of items and of everything inside them, as the
# id of each item to its count. A folder counts the words of all the
# documents inside it.
export def Totals(items: list<BI.BinderItem>, binderRoot: string): dict<number>
  var totals: dict<number> = {}
  var bufs: dict<number> = LoadedBufs()
  var sections: dict<list<string>> = SV.SectionTexts()
  def Walk(item: BI.BinderItem): number
    var words: number = 0
    if item.IsDoc()
      words = DocWords(item.AbsPath(binderRoot), bufs, sections)
    else
      for child in item.children
        words += Walk(child)
      endfor
    endif
    totals[item.id] = words
    return words
  enddef
  for item in items
    Walk(item)
  endfor
  return totals
enddef

# FUNCTION: Forget the counts of all files. The tests use it.
export def ClearCache(): void
  cache = {}
enddef
