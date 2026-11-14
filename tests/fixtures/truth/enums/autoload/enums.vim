vim9script

# Plugin_Name: Ghostcode
# A truth family: enums and their values. The line above each
# declaration states whether something uses it.
# License: GNU GPL 3.0

# LIVE
enum Color
  # LIVE
  Red,
  # GHOST
  Green
endenum

# GHOST
enum Dead
  # GHOST
  One
endenum

# LIVE
export enum Mode
  # LIVE
  On,
  # GHOST
  Off
endenum

# LIVE
enum Size
  # GHOST
  Small
endenum

# LIVE
def Fit(s: Size): void
  echo s
enddef

# LIVE
export def Run(): void
  echo Color.Red
  echo Fit
enddef
