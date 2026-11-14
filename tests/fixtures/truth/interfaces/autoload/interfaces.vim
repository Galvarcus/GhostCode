vim9script

# Plugin_Name: Ghostcode
# A truth family: interfaces and the classes that implement them. The
# line above each declaration states whether something uses it.
# License: GNU GPL 3.0

# LIVE
interface Shape
  def Area(): number
endinterface

# GHOST
interface Unused
  def Nope(): number
endinterface

# LIVE
class Square implements Shape
  # LIVE
  def Area(): number
    return 1
  enddef

  # GHOST
  def Edge(): number
    return 4
  enddef
endclass

# LIVE
export def Run(): void
  # LIVE
  var s: Shape = Square.new()
  echo s.Area()
enddef
