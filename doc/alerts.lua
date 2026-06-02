-- Pandoc Lua filter: convert docusaurus-style admonition fenced divs to
-- GitHub alert blockquotes (> [!TYPE] ...) for gfm output, or to
-- github-markdown-css-compatible divs for html output.
--
-- Docusaurus classes and their GitHub alert equivalents:
local MAP = {
    note = "NOTE",
    info = "NOTE",
    tip = "TIP",
    warning = "WARNING",
    caution = "CAUTION",
    danger = "WARNING",
}

function Div(el)
    local kind
    for _, c in ipairs(el.classes) do
        if MAP[c] then
            kind = MAP[c]
            break
        end
    end
    if not kind then
        return nil
    end

    if FORMAT:match("^html") then
        local lower = kind:lower()
        local label = kind:sub(1, 1) .. kind:sub(2):lower()
        local title = pandoc.RawBlock("html", '<p class="markdown-alert-title">' .. label .. "</p>")
        local content = { title }
        for _, b in ipairs(el.content) do
            content[#content + 1] = b
        end
        return pandoc.Div(content, pandoc.Attr("", { "markdown-alert", "markdown-alert-" .. lower }))
    end

    -- RawInline("markdown", ...) passes through the gfm writer unescaped, so
    -- the [!TYPE] marker reaches GitHub intact without bracket-escaping.
    local marker = pandoc.Para({ pandoc.RawInline("markdown", "[!" .. kind .. "]") })
    local content = { marker }
    for _, b in ipairs(el.content) do
        content[#content + 1] = b
    end
    return pandoc.BlockQuote(content)
end
