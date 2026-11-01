vim9script

##############################################################################
# Plugin_Name: Bartleby
# syntax/bartleby-compile-select.vim: highlighting for the compile
# selection pane, see RedrawSelect in compile.vim. As in
# syntax/bartleby-binder.vim, only the fixed lines and marks that
# Bartleby writes are matched. A document title is the user's own text
# and is never matched.
#
# No s:is_loaded guard: a syntax file runs once for every buffer.
# License: GNU GPL 3.0
##############################################################################

if exists('b:current_syntax')
  finish
endif

# Line 1 is the Compile header, and line 2 the project title.
syntax match bartlebyCompileSelectHeader /\%1l.*/
syntax match bartlebyCompileSelectTitle /\%2l.*/

# The checkbox of a document: x when included, a space when excluded. A
# folder has three spaces instead, so nothing here matches a folder row.
syntax match bartlebyCompileSelectChecked /\[x\]/
syntax match bartlebyCompileSelectUnchecked /\[ \]/

# The marker of a folder or a document. An alternation, not a bracket
# expression, see syntax/bartleby-binder.vim.
syntax match bartlebyCompileSelectMarker /\%(▸\|·\)\ze /

# A folder name: everything after the folder marker up to the slash that
# RenderSelectLines adds only to folder titles. Anchored on the folder
# marker, so a document title that ends in a slash never matches.
syntax match bartlebyCompileSelectDirectory /\%(▸ \)\@<=.*\/$/

highlight default link bartlebyCompileSelectHeader Title
highlight default link bartlebyCompileSelectTitle Title
highlight default link bartlebyCompileSelectChecked DiffAdd
highlight default link bartlebyCompileSelectUnchecked Comment
highlight default link bartlebyCompileSelectMarker Comment
highlight default link bartlebyCompileSelectDirectory Directory

b:current_syntax = 'bartleby-compile-select'
