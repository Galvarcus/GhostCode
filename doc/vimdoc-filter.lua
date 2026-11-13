-- Remove content between vimdoc ignore markers and omit images, then
-- give a help tag to the command and to each variable of the plugin.
local ignoring = false

-- The writer gives a tag to each heading alone, so `:help` finds no
-- command and no variable without the tags added here. A name gets one
-- tag, at the first place that defines it, because `:helptags` refuses
-- a tag that stands twice.
-- REFERENCE: https://github.com/Galvarcus/GhostCode/issues/76
local FORMAT = "vimdoc"
local WIDTH = 78
-- A user command at the start of a block of Vim code.
local COMMAND = "^(:%u%w*)"
-- A variable of a scope, as the one word of a table cell.
local VARIABLE = "^[gbwt]:[%w_]+$"
local tagged = {}

-- FUNCTION: The tag of a name, at the right margin as a help file of
-- Vim sets it, or nil where the name has its tag.
local function tag(name)
  if tagged[name] then return nil end

  tagged[name] = true
  local text = "*" .. name .. "*"
  return pandoc.RawBlock(FORMAT, string.rep(" ", WIDTH - #text) .. text)
end

-- FUNCTION: The variable that a table row defines, or nil. The row
-- defines one where its first cell holds one word of code and nothing
-- else.
local function variable(row)
  local cell = row.cells[1]
  local block = cell and #cell.contents == 1 and cell.contents[1]
  local code = block and block.content and #block.content == 1
    and block.content[1]

  if code and code.t == "Code" and code.text:match(VARIABLE) then
    return code
  end

  return nil
end

-- FUNCTION: A table of variables as one entry for each, the tag above
-- the name and the rest of the row below it, or nil for any other
-- table. A tag inside a cell would put `:help` on a row that the
-- columns of the table had made wider.
local function entries(tbl)
  local out = {}

  for _, body in ipairs(tbl.bodies) do
    for _, row in ipairs(body.body) do
      local code = variable(row)
      if not code then return nil end

      local rest = {}
      for i = 2, #row.cells do
        for _, block in ipairs(row.cells[i].contents) do
          table.insert(rest, block)
        end
      end

      local mark = tag(code.text)
      if mark then table.insert(out, mark) end
      table.insert(out, pandoc.DefinitionList({ { { code }, { rest } } }))
    end
  end

  return #out > 0 and out or nil
end

-- FUNCTION: The blocks with the tags in place.
local function with_tags(blocks)
  local out = {}

  for _, block in ipairs(blocks) do
    local made = block.t == "Table" and entries(block)

    if made then
      for _, b in ipairs(made) do table.insert(out, b) end
    else
      local cmd = block.t == "CodeBlock" and block.classes[1] == "vim"
        and block.text:match(COMMAND)
      local mark = cmd and tag(cmd)
      if mark then table.insert(out, mark) end
      table.insert(out, block)
    end
  end

  return out
end

function Pandoc(doc)
  local out = {}

  for _, block in ipairs(doc.blocks) do
    if block.t == "RawBlock" and block.format == "html" then
      local html = block.text
      if html:match("^%s*<!%-%-%s*vimdoc%-ignore%-start%s*%-%->%s*$") then
        ignoring = true
      elseif html:match("^%s*<!%-%-%s*vimdoc%-ignore%-end%s*%-%->%s*$") then
        ignoring = false
      elseif not ignoring then
        table.insert(out, block)
      end
    elseif not ignoring then
      if block.t == "Para" then
        local inlines = {}
        for _, inline in ipairs(block.content) do
          if inline.t ~= "Image" then table.insert(inlines, inline) end
        end
        if #inlines > 0 then table.insert(out, pandoc.Para(inlines)) end
      elseif block.t ~= "Image" then
        table.insert(out, block)
      end
    end
  end

  doc.blocks = with_tags(out)
  return doc
end
