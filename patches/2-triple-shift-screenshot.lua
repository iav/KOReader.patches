-- Take a screenshot by tapping Shift three times, as the stock Kindle
-- interface does. The built-in chord is Alt+Shift+G, which needs three
-- fingers; this needs one.
--
-- A "tap" is a Shift press and release with nothing in between, so holding
-- Shift for a chord (Shift+G, Shift+Home, ...) never counts. Three of them
-- within TAP_WINDOW fire the standard Screenshot event.
local Device = require("device")
if not Device:hasKeyboard() then return end

local input = Device.input
if input.triple_shift_screenshot then return end -- already patched
input.triple_shift_screenshot = true

local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local time = require("ui/time")

local KEY_RELEASE, KEY_PRESS, KEY_REPEAT = 0, 1, 2
local TAP_WINDOW = time.s(1.5)
local TAPS_NEEDED = 3

local shift_alone = false
local taps = 0
local last_tap = nil

local orig_handleKeyBoardEv = input.handleKeyBoardEv
input.handleKeyBoardEv = function(self, ev)
    local keycode = self.event_map[ev.code]
    if keycode == "Shift" then
        if ev.value == KEY_PRESS then
            -- A modifier already held means this is part of a chord.
            shift_alone = true
            for _, held in pairs(self.modifiers) do
                if held then
                    shift_alone = false
                    break
                end
            end
        elseif ev.value == KEY_REPEAT then
            shift_alone = false -- held down, not tapped
        elseif ev.value == KEY_RELEASE then
            if shift_alone then
                local now = time.now()
                taps = (last_tap and now - last_tap <= TAP_WINDOW) and taps + 1 or 1
                last_tap = now
                if taps >= TAPS_NEEDED then
                    taps, last_tap = 0, nil
                    UIManager:nextTick(function()
                        UIManager:sendEvent(Event:new("Screenshot"))
                    end)
                end
            end
            shift_alone = false
        end
    elseif ev.value == KEY_PRESS then
        shift_alone = false -- another key went down, Shift is a modifier here
        taps = 0
    end

    return orig_handleKeyBoardEv(self, ev)
end
