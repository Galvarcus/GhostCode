vim9script

##############################################################################
# Plugin_Name: Bartleby
# ftdetect/fountain.vim: gives .fountain files the fountain filetype,
# instead of whatever the user's Vim runtime guesses. syntax/fountain.vim
# and Spotlight's Fountain dialogue detection both need the filetype to be
# fountain.
# License: GNU GPL 3.0
##############################################################################
autocmd BufRead,BufNewFile *.fountain setfiletype fountain
