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
-- Anywhere:
--  E1: switch page
--
-- Main screen:
--  E2: record speed
--  E3: playback speed
--  SHIFT + E1: sampler model
--  K2: record start/stop
--  K3: playback start/stop
--
-- HW Sampler Instructions:
--  E2: record speed
--  E3: playback speed
--
-- Dirtying:
--  SHIFT + E1: preset
--  E2: sample rate
--  SHIFT + E2: sample rate (x 1k)
--  E3: bit depth

local rpmate = include('lib/librpmate')

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
