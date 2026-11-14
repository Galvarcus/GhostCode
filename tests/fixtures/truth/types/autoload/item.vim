vim9script

# Plugin_Name: Ghostcode
# A truth family: classes that only a type alias in another file names.
# The line above each declaration states whether something uses it.
# License: GNU GPL 3.0

# LIVE
export class Item
  # LIVE
  var label: string = 'item'
endclass

# GHOST
export class Other
  # GHOST
  var size: number = 0
endclass
