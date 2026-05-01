-- Pandoc Lua filter: convert docusaurus-style admonition fenced divs to
-- GitHub alert blockquotes (> [!TYPE] ...).
--
-- Docusaurus classes and their GitHub alert equivalents:
local MAP = {
    note    = "NOTE",
    info    = "NOTE",
    tip     = "TIP",
    warning = "WARNING",
    caution = "CAUTION",
    danger  = "WARNING",
}

function Div(el)
    local kind
    for _, c in ipairs(el.classes) do
        if MAP[c] then kind = MAP[c]; break end
    end
    if not kind then return nil end
    -- RawInline("markdown", ...) passes through the gfm writer unescaped, so
    -- the [!TYPE] marker reaches GitHub intact without bracket-escaping.
    local marker = pandoc.Para({pandoc.RawInline("markdown", "[!" .. kind .. "]")})
    local content = {marker}
    for _, b in ipairs(el.content) do content[#content + 1] = b end
    return pandoc.BlockQuote(content)
end
