-- rpmate.
--
-- @eigen
-- llllllll.co/t/rpmate
--
--
-- norns as a sampler budy.
--
-- K1 held is SHIFT
--
-- E2: record speed
-- E3: playback speed
-- SHIFT + E3: sampler model
--
-- K2: record start/stop
-- K3: playback start/stop

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
