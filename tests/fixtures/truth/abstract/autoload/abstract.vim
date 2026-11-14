vim9script

# Plugin_Name: Ghostcode
# A truth family: abstract classes and the classes that extend them.
# The line above each declaration states whether something uses it.
# License: GNU GPL 3.0

# LIVE
abstract class Base
  # LIVE
  abstract def Name(): string

  # LIVE
  abstract def Speak(): string

  # GHOST
  abstract def Unheard(): string

  # LIVE
  def Hello(): string
    return this.Name()
  enddef

  # GHOST
  def Never(): string
    return 'never'
  enddef
endclass

# GHOST
abstract class Alone
  # GHOST
  def Lost(): string
    return 'lost'
  enddef
endclass

# LIVE
class Leaf extends Base
  # LIVE
  def Name(): string
    return 'leaf'
  enddef

  # LIVE
  def Speak(): string
    return 'speak'
  enddef

  # GHOST
  def Unheard(): string
    return 'unheard'
  enddef
endclass

# LIVE
export def Run(): void
  # LIVE
  var l = Leaf.new()
  echo l.Hello() l.Speak()
enddef
