-- alerts.lua and replace.lua are pandoc Lua filters: pandoc runs them inside
-- its own interpreter, which injects the `pandoc` module along with the
-- FORMAT and PANDOC_SCRIPT_FILE globals, and invokes the filter callbacks
-- (Div, Pandoc) that the filter defines at the top level. Declare that
-- environment so luacheck does not report the pandoc API as undefined or
-- non-standard globals.
--
-- The recipe scripts under recipes/ are ordinary lua5.4 programs and are left
-- under luacheck's default configuration, so genuine stray globals there are
-- still caught.
local pandoc_filter = {
    read_globals = { "FORMAT", "PANDOC_SCRIPT_FILE", "pandoc" },
    globals = { "Div", "Pandoc" },
}
files["alerts.lua"] = pandoc_filter
files["replace.lua"] = pandoc_filter
