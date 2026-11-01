vim9script

##############################################################################
# Plugin_Name: Bartleby
# colors/bartleby.vim: the Bartleby colors for text consoles with 8 or 16
# colors, with a black background. Bartleby applies them at startup on such
# a console when no color scheme is set. Use the command colorscheme with
# the name of this file to apply them anywhere else. The colors are in
# autoload/bartleby/tty.vim.
#
# This script has no guard against loading twice: Vim sources it again each
# time the background option changes.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/tty.vim' as TY

TY.Apply(expand('<sfile>:t:r'))
