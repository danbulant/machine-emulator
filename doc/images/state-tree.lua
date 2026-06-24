-- Renders the machine state as a Merkle tree over the address space, as an SVG for a dark
-- background. Every complete subtree is a filled triangle with a root node at its apex: blue
-- for a named memory range, white for an elided pristine subtree. Internal nodes are circles
-- joined by edges, colored by what their subtree holds: blue if all ranges, white if all
-- pristine, gray if mixed. A gap that straddles a split boundary is two triangles (one from
-- above, one from below) sharing a single band in the bar. Band height is proportional to
-- log2 of the whole span; a shared band splits it between its triangles by each one's log2
-- span (since log2(B + C) is not log2(B) + log2(C), the parts are scaled to add up). Run as
-- `lua5.4 state-tree.lua > state-tree.svg`.
local cartesi = require("cartesi")
local util = require("cartesi.util")
local m = cartesi.machine({
    ram = { length = 64 << 20 },
    flash_drive = { { length = 128 << 20 } },
    nvram = { { length = 8 << 20 } },
})
local TWO64 = 2.0 ^ 64
local function lg(x)
    return math.log(x, 2)
end
local function rowh(span)
    return 9 + 1.8 * lg(span)
end
local function hex(a)
    return string.format("0x%013x", math.tointeger(a) or math.tointeger(math.floor(a)) or 0)
end

local FONT = "-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif"
local MONO = "ui-monospace,SFMono-Regular,Menlo,Consolas,monospace"
-- Palette per theme. The first argument selects "light" or "dark" (default), so a
-- <picture> in the page can serve the variant that matches the reader's theme. BLUE
-- (range fill) and GRAY (mixed node) read on both backgrounds; the rest flip.
local THEMES = {
    dark = { FG = "#e6edf3", MUT = "#9aa4b2", EDGE = "#b9c2cf", WHITE = "#ffffff", BLUE_T = "#5b9bf0" },
    light = { FG = "#1f2328", MUT = "#6e7781", EDGE = "#57606a", WHITE = "#eaeef2", BLUE_T = "#0969da" },
}
local theme = THEMES[arg[1]] or THEMES.dark
local FG, MUT, EDGE, WHITE, BLUE_T = theme.FG, theme.MUT, theme.EDGE, theme.WHITE, theme.BLUE_T
local BLUE, GRAY = "#2f6fb3", "#8b949e"

local ranges = {}
for _, r in ipairs(m:get_address_ranges()) do
    if r.is_memory then
        ranges[#ranges + 1] = { start = r.start, len = r.length, desc = r.description }
    end
end
table.sort(ranges, function(a, b)
    return a.start < b.start
end)

-- All ranges fully contained in the address interval [lo, hi).
local function rangesin(lo, hi)
    local t = {}
    for _, r in ipairs(ranges) do
        if r.start >= lo and r.start + r.len <= hi then
            t[#t + 1] = r
        end
    end
    return t
end

-- Binary Merkle tree by address bisection, contracting all-pristine subtrees to one triangle.
-- A leaf is either a memory range, or a pristine interval { tlo, thi }.
local function build(lo, hi)
    local upper, lower, core
    while true do
        local within = rangesin(lo, hi)
        if #within == 0 then
            core = { tlo = lo, thi = hi }
            break
        end
        if #within == 1 and within[1].start == lo and within[1].start + within[1].len == hi then
            core = within[1]
            break
        end
        local mid = lo + (hi - lo) / 2
        local nl, nr = 0, 0
        for _, r in ipairs(within) do
            if r.start < mid then
                nl = nl + 1
            else
                nr = nr + 1
            end
        end
        if nl > 0 and nr > 0 then
            core = { l = build(lo, mid), r = build(mid, hi) }
            break
        elseif nr == 0 then
            upper = { tlo = mid, thi = upper and upper.thi or hi }
            hi = mid
        else
            lower = { tlo = lower and lower.tlo or lo, thi = mid }
            lo = mid
        end
    end
    if upper then
        core = { l = core, r = upper }
    end
    if lower then
        core = { l = lower, r = core }
    end
    return core
end
local tree = build(0, TWO64)

-- Node color: blue if its subtree holds only ranges, white if only pristine, gray if mixed.
local function classify(n)
    if n.desc then
        return true, false
    end
    if n.tlo then
        return false, true
    end
    local lr, lp = classify(n.l)
    local rr, rp = classify(n.r)
    return lr or rr, lp or rp
end
local function colorof(n)
    local hr, hp = classify(n)
    if hr and hp then
        return GRAY
    elseif hr then
        return BLUE
    else
        return WHITE
    end
end

local function is_leaf(n)
    return n.desc ~= nil or n.tlo ~= nil
end
local rows = {}
local function inorder(n)
    if is_leaf(n) then
        rows[#rows + 1] = n
    else
        inorder(n.l)
        inorder(n.r)
    end
end
inorder(tree)

local TOP, BAR_W, DX, TRI_W = 26, 22, 50, 18
local BAR_X = 40 + 7 * DX
local GAP = 8 -- horizontal gap so leaf triangles do not touch the address-space bar
local X_LEAF = BAR_X - GAP

-- Geometry. Each band's height is rowh of its whole span; a band shared by several pristine
-- triangles splits that height among them in proportion to each triangle's log2 span.
local bands = {}
local y, i = TOP, 1
while i <= #rows do
    local lf = rows[i]
    if lf.tlo then
        local j = i
        while j < #rows and rows[j + 1].tlo do
            j = j + 1
        end
        local top = y
        local height = rowh(rows[j].thi - rows[i].tlo)
        local sum = 0
        for k = i, j do
            sum = sum + lg(rows[k].thi - rows[k].tlo)
        end
        for k = i, j do
            local hh = height * lg(rows[k].thi - rows[k].tlo) / sum
            rows[k].y0, rows[k].h, rows[k].cy = y, hh, y + hh / 2
            y = y + hh
        end
        bands[#bands + 1] = { pristine = true, top = top, bot = y, start = rows[i].tlo }
        i = j + 1
    else
        lf.h = rowh(lf.len)
        lf.y0, lf.cy = y, y + lf.h / 2
        bands[#bands + 1] = { range = lf }
        y = y + lf.h
        i = i + 1
    end
end
local BAR_BOT = y

-- Lay out the tree right-to-left: each node sits one column left of its deeper child.
local edges, dots = {}, {}
local function layout(n)
    if is_leaf(n) then
        return X_LEAF - TRI_W, n.cy, 0
    end
    local lcx, ly, lh = layout(n.l)
    local rcx, ry, rh = layout(n.r)
    local h = math.max(lh, rh) + 1
    local x, cy = X_LEAF - h * DX, (ly + ry) / 2
    edges[#edges + 1] = { x, cy, lcx, ly }
    edges[#edges + 1] = { x, cy, rcx, ry }
    dots[#dots + 1] = { x = x, y = cy, color = colorof(n) }
    return x, cy, h
end
local rootx = layout(tree)

-- Bounds: the root sits far to the left, the range labels extend to the right. Compute the
-- real extent and shift the whole drawing into a padded viewport with room for the headers.
local TX = BAR_X + BAR_W + 8
local maxr = TX + 60
for _, b in ipairs(bands) do
    if b.range then
        local label = string.format("%s (2^%d bytes)", b.range.desc, util.ilog2(b.range.len))
        maxr = math.max(maxr, TX + #label * 6.6)
    end
end
local PAD, HEADER = 16, 34
local SHIFT = PAD - rootx
local W, H = SHIFT + maxr + 12, HEADER + BAR_BOT + 16

local s = {}
local function p(...)
    s[#s + 1] = string.format(...)
end
p('<svg xmlns="http://www.w3.org/2000/svg" width="%g" height="%g" font-family="%s">', W, H, FONT)
p(
    '<text x="%g" y="22" font-size="14" font-weight="bold" text-anchor="middle" fill="%s">State hash-tree</text>',
    SHIFT + (rootx + X_LEAF - TRI_W) / 2,
    FG
)
p(
    '<text x="%g" y="22" font-size="14" font-weight="bold" text-anchor="middle" fill="%s">Address space</text>',
    SHIFT + (BAR_X + maxr) / 2,
    FG
)
p('<g transform="translate(%g,%g)">', SHIFT, HEADER)
for _, e in ipairs(edges) do
    p('<line x1="%g" y1="%g" x2="%g" y2="%g" stroke="%s"/>', e[1], e[2], e[3], e[4], EDGE)
end
for _, b in ipairs(bands) do
    if b.pristine then
        p(
            '<rect x="%g" y="%g" width="%g" height="%g" fill="%s" stroke="%s"/>',
            BAR_X,
            b.top,
            BAR_W,
            b.bot - b.top,
            WHITE,
            EDGE
        )
        p(
            '<text x="%g" y="%g" font-size="10" font-family="%s" fill="%s">%s</text>',
            TX,
            b.top + 4,
            MONO,
            MUT,
            hex(b.start)
        )
        p(
            '<text x="%g" y="%g" font-size="12" font-style="italic" fill="%s">pristine</text>',
            TX,
            (b.top + b.bot) / 2 + 4,
            WHITE
        )
    else
        local lf = b.range
        p('<rect x="%g" y="%g" width="%g" height="%g" fill="%s" stroke="%s"/>', BAR_X, lf.y0, BAR_W, lf.h, BLUE, EDGE)
        p(
            '<text x="%g" y="%g" font-size="10" font-family="%s" fill="%s">%s</text>',
            TX,
            lf.y0 + 4,
            MONO,
            MUT,
            hex(lf.start)
        )
        p(
            '<text x="%g" y="%g" font-size="13" fill="%s">%s '
                .. '<tspan fill="%s" font-size="10">(2^%d bytes)</tspan></text>',
            TX,
            lf.cy + 4,
            BLUE_T,
            lf.desc,
            MUT,
            util.ilog2(lf.len)
        )
    end
end
p('<text x="%g" y="%g" font-size="10" font-family="%s" fill="%s">2^64</text>', TX, BAR_BOT + 4, MONO, MUT)
for _, lf in ipairs(rows) do
    local fill = lf.tlo and WHITE or BLUE
    p(
        '<polygon points="%g,%g %g,%g %g,%g" fill="%s" stroke="%s"/>',
        X_LEAF - TRI_W,
        lf.cy,
        X_LEAF,
        lf.y0 + 0.5,
        X_LEAF,
        lf.y0 + lf.h - 0.5,
        fill,
        EDGE
    )
    p('<circle cx="%g" cy="%g" r="3.5" fill="%s" stroke="%s"/>', X_LEAF - TRI_W, lf.cy, fill, EDGE)
end
for _, d in ipairs(dots) do
    p('<circle cx="%g" cy="%g" r="3.5" fill="%s" stroke="%s"/>', d.x, d.y, d.color, EDGE)
end
p("</g>")
p("</svg>")
io.write(table.concat(s, "\n"), "\n")
