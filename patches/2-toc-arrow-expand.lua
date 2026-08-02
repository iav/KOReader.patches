-- Arrow-key expand/collapse for ToC subtrees on non-touch d-pad devices:
-- the right arrow expands the focused node, the left one collapses it
-- (swapped in mirrored UI layout), and the focus stays on the node.
-- Upstream: https://github.com/koreader/koreader/pull/15780
-- Self-disables once the upstream fix is present.
local ReaderToc = require("apps/reader/modules/readertoc")
if ReaderToc.refocusTocNode then return end -- upstream has it

local Device = require("device")
if not Device:hasDPad() or Device:hasFewKeys() then return end

local BD = require("ui/bidi")

local orig_onShowToc = ReaderToc.onShowToc
ReaderToc.onShowToc = function(self)
    local ret = orig_onShowToc(self)
    local toc_menu = self.toc_menu
    if not toc_menu or toc_menu.onExpandCurrentNode then return ret end

    toc_menu.key_events.FocusRight = nil
    toc_menu.key_events.FocusLeft = nil
    local expand_key, collapse_key = "Right", "Left"
    if BD.mirroredUILayout() then
        expand_key, collapse_key = collapse_key, expand_key
    end
    toc_menu.key_events.ExpandCurrentNode = { { expand_key } }
    toc_menu.key_events.CollapseCurrentNode = { { collapse_key } }

    local function toggle(menu, icon, toggler)
        local focused_widget = menu:getFocusItem()
        local item = focused_widget and focused_widget.entry
        if item and item.state and item.state.icon == icon then
            -- Pre-set the focus restore target: the node keeps its list
            -- position across the toggle (children are inserted/removed
            -- below it), and the rebuild consumes Menu.itemnumber.
            local node = self.filtered_toc[item.index]
            for i, v in ipairs(self.collapsed_toc) do
                if v == node then
                    menu.itemnumber = i
                    break
                end
            end
            toggler(self, item.index)
        end
        return true
    end
    toc_menu.onExpandCurrentNode = function(menu)
        return toggle(menu, "control.expand", self.expandToc)
    end
    toc_menu.onCollapseCurrentNode = function(menu)
        return toggle(menu, "control.collapse", self.collapseToc)
    end
    return ret
end
