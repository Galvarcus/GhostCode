vim9script

# Plugin_Name: Ghostcode
# A truth family: abstract classes and the classes that extend them.
# The line above each declaration states whether something uses it.
# License: GNU GPL 3.0

# LIVE
abstract class Base
  # LIVE
  def Hello(): string
    return 'hello'
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
endclass

# LIVE
export def Run(): void
  # LIVE
  var l = Leaf.new()
  echo l.Hello()
  echo l.Name()
enddef
