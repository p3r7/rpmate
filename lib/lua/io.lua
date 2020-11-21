--
-- IO
--


-- -------------------------------------------------------------------------
-- STATE

local shift = false
local screen_dirty = false

local redraw_fps = 30
local redraw_clock


-- -------------------------------------------------------------------------
-- INIT / CLEANUP


function init_screen_redraw()
  -- co-routine: screen redraw
  redraw_clock = clock.run(
    function()
      local step_s = 1 / redraw_fps
      print("waiting for "..step_s.." seconds")
      while true do
        clock.sleep(step_s)
        if is_screen_dirty() then
          redraw()
          unmark_screen_dirty()
        end
      end
  end)
end

function cleanup_screen_redraw()
  clock.cancel(redraw_clock)
end


-- -------------------------------------------------------------------------
-- ACCESSORS: SHIFT

function is_shift_on()
  return shift
end

function shift_on()
  shift = true
end

function shift_off()
  shift = false
end


-- -------------------------------------------------------------------------
-- ACCESSORS: SCREEN

function is_screen_dirty()
  return screen_dirty
end

function mark_screen_dirty()
  screen_dirty = true
end

function unmark_screen_dirty()
  screen_dirty = false
end
