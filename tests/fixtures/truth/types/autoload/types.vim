vim9script

# Plugin_Name: Ghostcode
# A truth family: type aliases. The line above each declaration states
# whether something uses it.
# License: GNU GPL 3.0

import autoload './item.vim' as I

# LIVE
type Amount = number

# GHOST
type Unused = list<string>

# LIVE
export type Lines = list<string>

# LIVE
type Entry = I.Item

# GHOST
type Lost = I.Other

# LIVE
def Total(amounts: list<Amount>): Amount
  return reduce(amounts, (acc, a) => acc + a, 0)
enddef

# LIVE
def Label(e: Entry): string
  return e.label
enddef

# LIVE
export def Run(): void
  # LIVE
  var lines: Lines = [string(Total([1, 2]))]
  echo lines Label(Entry.new())
enddef
