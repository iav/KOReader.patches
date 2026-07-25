--[[--
Unblock SIGALRM that a third-party launcher left blocked in our signal mask.

Some Kindle launchers use an interval timer of their own and block SIGALRM while
they run.  The MobileRead hotkey manager `launchpad` is the known case: it arms an
interval timer to time out hotkey sequences (see its README, "engages the interval
timer to trigger after specified HotInterval milliseconds") and does not restore the
signal mask before exec'ing the program the hotkey launches.

A signal mask is inherited across fork() and *preserved across execve()*, so the
block silently propagates into KOReader and into every helper KOReader spawns.  The
helper cannot detect or undo it.  That breaks any CLI tool implementing its timeouts
with alarm()/setitimer():

  * `ntpdate` (Synchronize time) -- sends one request and waits forever; even its
    own `-t` option is implemented via SIGALRM, so it does not help;
  * `ping` (Show network info) -- sends the first packet and never sends another.

The alarm is raised but, being blocked, only becomes pending (visible as SigBlk and
ShdPnd both holding bit 14 in /proc/<pid>/status).  It is never delivered, the helper
never returns, and a synchronous os.execute() hangs the KOReader UI for good -- on a
non-touch device the only way out is a power cycle.

Unblocking SIGALRM once, here, is enough: the corrected mask is inherited by
everything we spawn afterwards.

This is a no-op unless the signal really is blocked, so it is safe on every platform.
--]]--

local ffi = require("ffi")
local bit = require("bit")
local logger = require("logger")

local SIGALRM = 14
local SIG_UNBLOCK = 1

-- Read the blocked-signal mask of our own process.
-- SigBlk is printed as one big-endian 64-bit hex number, so bits 0-15 -- the range
-- SIGALRM lives in -- are the last four hex digits.  Parsing only those keeps us
-- clear of the precision limit of a Lua number.
local function isSigAlrmBlocked()
    local status = io.open("/proc/self/status", "r")
    if not status then
        return false -- not Linux, or no procfs: nothing we can check
    end
    local sigblk = status:read("*a"):match("SigBlk:%s*(%x+)")
    status:close()
    if not sigblk then
        return false
    end
    local low_bits = tonumber(sigblk:sub(-4), 16)
    return low_bits ~= nil and bit.band(low_bits, bit.lshift(1, SIGALRM - 1)) ~= 0
end

if not isSigAlrmBlocked() then
    return
end

-- koreader-base's posix_h does not declare any of the signal API, so declare the
-- little we need under private names.
-- sigset_t is a fixed 1024-bit array on Linux; 32 longs cover it on 32-bit and
-- over-allocate harmlessly on 64-bit.  We only ever pass a pointer to it.
local ok = pcall(ffi.cdef, [[
    typedef struct { unsigned long ko_sigset_val[32]; } ko_sigset_t;
    int sigprocmask(int how, const ko_sigset_t *set, ko_sigset_t *oldset);
]])
if not ok then
    logger.warn("unblock-sigalrm: could not declare sigprocmask")
    return
end

local set = ffi.new("ko_sigset_t") -- zero-initialised by LuaJIT
-- Signal numbers are 1-based, the bits in a sigset_t are 0-based.
set.ko_sigset_val[0] = bit.lshift(1, SIGALRM - 1)

if ffi.C.sigprocmask(SIG_UNBLOCK, set, nil) ~= 0 then
    logger.warn("unblock-sigalrm: sigprocmask() failed")
elseif isSigAlrmBlocked() then
    logger.warn("unblock-sigalrm: SIGALRM still blocked after sigprocmask()")
else
    logger.info("unblock-sigalrm: SIGALRM was blocked by the launcher, unblocked it")
end
