-- rpmate.
--
-- @eigenbahn
-- llllllll.co/t/rpmate
--
--
-- hold btn 1 for settings
-- btn 2 play / pause
-- btn 3 rec on/off
--
-- enc 1 - switch track
-- enc 2 - change speed
-- enc 3 - overdub level

local rpmate = include('rpmate/lib/librpmate')

function init()
  rpmate.active = true
  rpmate.init()
end

function key(n,z)
  rpmate:key(n,z)
end

function enc(n,d)
  rpmate:enc(n,d)
end

function redraw()
  rpmate:redraw()
end

function cleanup()
  rpmate:cleanup()
end
