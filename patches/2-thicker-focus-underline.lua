-- Make the focus underline thick enough to see on an old Kindle, without fattening the separators.
--
-- KOReader draws both things with the same widget: every menu item ends in an UnderlineContainer,
-- painted in line_color (dark grey) normally and in black while the item holds the focus. At
-- 167 dpi the stock line is 1 px in Menu (Size.line.medium) and 1.5 px elsewhere, which on an eInk
-- Pearl screen is barely distinguishable from the separator above it.
--
-- Simply raising the size thickens the separators too, so instead the container keeps reserving the
-- thick line's height while painting a thin one until the item is focused. Height therefore never
-- changes and nothing reflows -- which is what upstream ran into when it tried to swap the size in
-- MenuItem:onFocus (see the commented-out attempt there) and backed the change out.
--
-- Covers Menu (file browser, history, OPDS catalogs, plugin lists), TouchMenuItem and ConfigDialog.

local Device = require("device")
if not Device:hasDPad() then return end -- focus underlines only matter where a d-pad walks them

local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local Menu = require("ui/widget/menu")
local Size = require("ui/size")
local UnderlineContainer = require("ui/widget/container/underlinecontainer")
local logger = require("logger")

-- Size.line.focus_indicator is KOReader's own "this is focused" thickness -- coverbrowser's mosaic
-- view already draws with it. It also comes out close to the bar the native Kindle UI puts under
-- the selected row.
local FOCUS_LINE_SIZE = Size.line.focus_indicator
local IDLE_LINE_SIZE = Size.line.medium -- the stock thickness, kept for unfocused items

Menu.linesize = FOCUS_LINE_SIZE
UnderlineContainer.linesize = FOCUS_LINE_SIZE

-- Same as upstream's paintTo, except the painted line is thinner than the reserved space unless
-- the item is focused. MenuItem/TouchMenuItem signal focus by setting the colour to black.
function UnderlineContainer:paintTo(bb, x, y)
    local container_size = self:getSize()
    if not self.dimen then
        self.dimen = Geom:new{
            x = x, y = y,
            w = container_size.w,
            h = container_size.h,
        }
    else
        self.dimen.x = x
        self.dimen.y = y
    end

    local line_width = self.line_width or self.dimen.w
    local line_x = x
    if BD.mirroredUILayout() then
        line_x = line_x + self.dimen.w - line_width
    end

    local content_size = self[1]:getSize()
    local p_y = y
    if self.vertical_align == "center" then
        p_y = math.floor((container_size.h - content_size.h) / 2) + y
    elseif self.vertical_align == "bottom" then
        p_y = (container_size.h - content_size.h) + y
    end
    self[1]:paintTo(bb, x, p_y)

    local focused = self.color == Blitbuffer.COLOR_BLACK
    local drawn_size = focused and self.linesize or math.min(IDLE_LINE_SIZE, self.linesize)
    bb:paintRect(line_x, y + container_size.h - drawn_size,
        line_width, drawn_size, self.color)
end

logger.info("focus underline patch: focused", FOCUS_LINE_SIZE, "px, idle", IDLE_LINE_SIZE, "px")
