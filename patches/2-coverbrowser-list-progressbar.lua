-- 2-coverbrowser-list-progressbar.lua
--
-- CoverBrowser "Detailed list" mode: draw a reading-progress bar (frame + fill,
-- like the reader's bottom progress bar) in each book row, in addition to the
-- existing "N % of M pages" text.
--
-- Requirements (iav):
--   * bar in every row that shows a %, bottom-right of the row, under the % text;
--   * must NOT overlap the bottom-right dogear ("corner mark") of opened books;
--   * SAME fixed length for all books and SAME horizontal X across rows, so the
--     fill position (progress) is visually comparable between books.
--
-- Delivery note: ListMenuItem is file-local in listmenu.lua (the module returns
-- ListMenu). We reach it as an upvalue of ListMenu._updateItemsBuildUI via
-- userpatch.getUpValue, after the plugin is instantiated. Pure UI overlay,
-- safe on any device; only active when the CoverBrowser plugin is enabled.

local userpatch = require("userpatch")

local function patch_coverbrowser(_plugin)
    local ok, ListMenu = pcall(require, "listmenu")
    if not ok or type(ListMenu) ~= "table" or not ListMenu._updateItemsBuildUI then
        return
    end
    local ListMenuItem = userpatch.getUpValue(ListMenu._updateItemsBuildUI, "ListMenuItem")
    if not ListMenuItem or ListMenuItem.__pbar_patched then
        return
    end
    ListMenuItem.__pbar_patched = true

    local Blitbuffer = require("ffi/blitbuffer")
    local ProgressWidget = require("ui/widget/progresswidget")
    local Size = require("ui/size")
    local Screen = require("device").screen
    local BD = require("ui/bidi")

    -- One shared progress widget, recreated only if the fixed width changes.
    local pbar
    local pbar_w = -1
    local BAR_W = Screen:scaleBySize(90)   -- FIXED width => identical bar length for all books
    local BAR_H = Screen:scaleBySize(7)

    local function getBar(width)
        if not pbar or pbar_w ~= width then
            pbar_w = width
            pbar = ProgressWidget:new{
                width      = width,
                height     = BAR_H,
                margin_h   = Screen:scaleBySize(1),
                radius     = Size.border.thin,
                bordersize = Size.border.default,
                bordercolor = Blitbuffer.COLOR_BLACK,
                bgcolor    = Blitbuffer.COLOR_WHITE,
                fillcolor  = Blitbuffer.COLOR_BLACK,
            }
        end
        return pbar
    end

    -- Wrap update(): stash the same progress values the row text uses, so paintTo
    -- needs no DB lookup.
    local orig_update = ListMenuItem.update
    function ListMenuItem:update()
        orig_update(self)
        self._pbar_percent = nil
        self._pbar_status = nil
        if self.menu and self.menu.getBookInfo and self.filepath then
            local ok_bi, book_info = pcall(self.menu.getBookInfo, self.filepath)
            if ok_bi and book_info then
                self._pbar_percent = book_info.percent_finished
                self._pbar_status = book_info.status
            end
        end
    end

    -- Wrap paintTo(): draw the bar as an overlay with absolute, fixed geometry.
    local orig_paintTo = ListMenuItem.paintTo
    function ListMenuItem:paintTo(bb, x, y)
        orig_paintTo(self, bb, x, y)

        local percent = self._pbar_percent
        if percent == nil then return end          -- no % shown (or a directory) => no bar
        local status = self._pbar_status
        if status == "complete" then
            percent = 1
        end

        local bar = getBar(BAR_W)
        bar.fillcolor = (status == "abandoned")
            and Blitbuffer.COLOR_GRAY_6 or Blitbuffer.COLOR_BLACK

        local right_pad      = Screen:scaleBySize(10)       -- = wright_right_padding
        local corner_reserve = math.floor(self.height / 6)  -- = corner_mark_size (dogear)
        local gap_x          = Screen:scaleBySize(4)
        local gap_y          = Screen:scaleBySize(3)

        local pos_x
        if BD.mirroredUILayout() then
            pos_x = x + right_pad + corner_reserve + gap_x
        else
            pos_x = x + self.width - right_pad - corner_reserve - gap_x - BAR_W
        end
        local pos_y = y + self.height - BAR_H - gap_y

        bar:setPercentage(percent)
        bar:paintTo(bb, pos_x, pos_y)
    end
end

userpatch.registerPatchPluginFunc("coverbrowser", patch_coverbrowser)
