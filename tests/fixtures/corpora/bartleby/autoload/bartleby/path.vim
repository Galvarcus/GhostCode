vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# path.vim: one spelling of a path, so that two names of one file compare
# equal. Windows gives three: fnamemodify(':p') answers with backslashes
# and the long name, a scrive stores forward slashes, and tempname and the
# environment answer with the 8.3 short name, as
# C:\Users\RUNNER~1\AppData\Local\Temp for C:\Users\runneradmin\... .
# Bartleby keys buffers by path, asks whether a document is under the
# binder root, and cuts a relative path out of an absolute one, and each of
# those compared text, so one file was two files.
#
# Canon is for a key and for a comparison, never for what a user reads or
# what goes in a file, because it folds case wherever Vim says the file
# system folds it, which fileignorecase answers and which covers macOS as
# well as Windows. Rel keeps the case of the path it is given, so what a
# scrive stores stays as it was.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/48
# License: GNU GPL 3.0
##############################################################################

const SEP: string = '/'
# One backslash, as a pattern.
const BACKSLASH_PAT: string = '\\'
const TRAIL_PAT: string = '/\+$'
# Whether a backslash separates a path here. options.txt gives this as the
# test for it under shellslash. Elsewhere a backslash is a character of a
# name, and turning it around would name another file.
const BACKSLASH_IS_SEP: bool = exists('+shellslash') != 0

# FUNCTION: Return path as one absolute path, with forward slashes and no
# trailing slash, and the links in it left as they are, keeping its case.
# Empty for an empty path, because fnamemodify answers the current folder
# for one, which is nobody's file.
def Spelled(path: string): string
  if path ==# ''
    return ''
  endif
  var abs: string = fnamemodify(path, ':p')
  if BACKSLASH_IS_SEP
    abs = substitute(abs, BACKSLASH_PAT, SEP, 'g')
  endif
  return substitute(abs, TRAIL_PAT, '', '')
enddef

# FUNCTION: Return path as Spelled does, with its symbolic links resolved.
def Full(path: string): string
  return path ==# '' ? '' : Spelled(resolve(fnamemodify(path, ':p')))
enddef

# FUNCTION: Return text with its case folded where the file system folds
# it. Vim answers that with fileignorecase, which options.txt gives as on
# by default where case in file names is normally ignored, naming
# MS-Windows and macOS. It is read on each call because the writer may set
# it at any time. It is exported for layout.vim, which asks this question
# of a name beside two others that it must not be confused with.
export def Folded(text: string): string
  return &fileignorecase ? tolower(text) : text
enddef

# FUNCTION: Return true when p, already a Full path, lies under r, also a
# Full path. The prefix is compared as Canon compares, and the length
# comes from the paths themselves, never from a folded one, because
# folding a character can change how many bytes it takes.
def Below(r: string, p: string): bool
  return r !=# '' && len(p) > len(r) && p[len(r)] ==# SEP
    && Folded(strpart(p, 0, len(r))) ==# Folded(r)
enddef

# FUNCTION: Return the one spelling of path to compare by, or to key a
# dictionary by. Not for display and not for a file, see the header.
export def Canon(path: string): string
  return Folded(Full(path))
enddef

# FUNCTION: Return the one spelling of path to compare by, with the links
# in it left as they are. For a comparison that must tell a link from what
# it points at, where resolving both sides would make them equal.
export def CanonUnresolved(path: string): string
  return Folded(Spelled(path))
enddef

# FUNCTION: Return true when a and b name one file. False when either is
# empty, because an empty path names none.
export def Same(a: string, b: string): bool
  var one: string = Canon(a)
  return one !=# '' && one ==# Canon(b)
enddef

# FUNCTION: Return true when path is root itself or lies under it.
export def Under(root: string, path: string): bool
  var r: string = Full(root)
  var p: string = Full(path)
  return r !=# '' && p !=# '' && (Folded(p) ==# Folded(r) || Below(r, p))
enddef

# FUNCTION: Return the part of path below root, with forward slashes and
# the case that path has, or an empty string when path is not under root.
# It takes the place of a slice by the length of the root, which answered
# with part of the root whenever the two were spelled differently.
export def Rel(root: string, path: string): string
  var r: string = Full(root)
  var p: string = Full(path)
  return Below(r, p) ? p[len(r) + 1 : ] : ''
enddef
