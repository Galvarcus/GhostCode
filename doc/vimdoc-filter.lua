-- Remove content between vimdoc ignore markers and omit images.
local ignoring = false

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

  doc.blocks = out
  return doc
end
