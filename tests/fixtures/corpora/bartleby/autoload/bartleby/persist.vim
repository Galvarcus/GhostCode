vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# persist.vim: reads and writes JSON files: a dict in, a dict out. It
# knows nothing of projects or the Binder. Its callers, such as
# project.vim and document.vim, do.
#
# A write goes to a temporary file first, which then replaces the file in
# one step, so that a crash or a full disk leaves the old file or the new
# one, never a part of one.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/log.vim' as L
import autoload 'bartleby/locale/data.vim' as MD
import autoload 'bartleby/path.vim' as PA

var log = L.New(expand('<sfile>:t'))

# The suffix of the file that a write fills before it replaces the file.
# Exported because a caller that budgets a path against a limit must
# count what a write appends to it, which is longer than the path the
# write leaves behind.
export const TMP_SUFFIX: string = '.tmp'
# The suffix of the copy of a file before its last write, see WriteJson.
export const BACKUP_SUFFIX: string = '.bak'

export def ReadJson(path: string): dict<any>
  if !filereadable(path)
    log.Warn(MD.NoSuchFile(path))
    return {}
  endif
  try
    return json_decode(join(readfile(path), "\n"))
  catch
    log.Exception()
    return {}
  endtry
enddef

# FUNCTION: Write data to path as JSON, into a temporary file that then
# replaces path. With keepBackup, the file as it was is copied first, to
# path with BACKUP_SUFFIX. Returns false, with an error, when a step fails.
# path is then as it was.
export def WriteJson(path: string, data: dict<any>, keepBackup: bool = false): bool
  var temporary: string = path .. TMP_SUFFIX
  try
    var dir: string = fnamemodify(path, ':h')
    if !isdirectory(dir)
      mkdir(dir, 'p')
    endif
    if writefile([json_encode(data)], temporary) != 0
      return WriteFailed(path, temporary)
    endif
    if keepBackup && filereadable(path)
        && writefile(readfile(path, 'b'), path .. BACKUP_SUFFIX, 'b') != 0
      return WriteFailed(path, path .. BACKUP_SUFFIX)
    endif
    if rename(temporary, path) != 0
      return WriteFailed(path, temporary)
    endif
  catch
    return WriteFailed(path, v:exception)
  endtry
  return true
enddef

# FUNCTION: Report that path was not written, because of detail, and remove
# the temporary file. Returns false, for WriteJson to return.
def WriteFailed(path: string, detail: string): bool
  log.Error(MD.CouldNotWritten(path, detail))
  var temporary: string = path .. TMP_SUFFIX
  if filereadable(temporary)
    delete(temporary)
  endif
  return false
enddef

# FUNCTION: Remove dir, and each folder above it, while it is empty, up to
# root, which stays.
#
# path.vim answers both questions about the two paths, because a scrive
# stores its root with forward slashes while Vim answers with the
# separator of its own system, and either may be spelled in another case.
# Compared as text, the walk never began.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/51
export def RemoveEmptyDirectories(dir: string, root: string): void
  var current: string = dir
  while !PA.Same(current, root) && PA.Under(root, current)
      && isdirectory(current) && empty(readdir(current))
    delete(current, 'd')
    current = fnamemodify(current, ':h')
  endwhile
enddef
