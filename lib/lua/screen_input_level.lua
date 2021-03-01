--
-- screen_input_level
--


include('lib/lua/io')
include('lib/lua/ui')


-- -------------------------------------------------------------------------
-- STATE

local signal = { amp_in_l = 0, amp_in_r = 0, amp_in_l_max = 0, amp_in_r_max = 0 }
local p_amp_in_l
local p_amp_in_r

function repoll_input_level()
  p_amp_in_r:update()
  p_amp_in_l:update()
end

local input_level_poll_clock

-- local in_l, in_r =  0, 0


-- -------------------------------------------------------------------------
-- INIT / CLEANUP

function init_input_level_poll()
  audio.monitor_stereo()

  -- local vu_l, vu_r = poll.set("amp_in_l"), poll.set("amp_in_r")
  -- vu_l.time, vu_r.time = 1 / 30, 1 / 30
  -- vu_l.callback = function(val) in_l = val * 100 end
  -- vu_r.callback = function(val) in_r = val * 100 end
  -- vu_l:start()
  -- vu_r:start()

  p_amp_in_l = poll.set("amp_in_l")
  p_amp_in_l.time = 1 / 15
  p_amp_in_l.callback = function(val)
    signal.amp_in_l = val
    if signal.amp_in_l > signal.amp_in_l_max then
      signal.amp_in_l_max = signal.amp_in_l
    end
  end
  p_amp_in_r = poll.set("amp_in_r")
  p_amp_in_r.time = 1 / 15
  p_amp_in_r.callback = function(val)
    signal.amp_in_r = val
    if signal.amp_in_r > signal.amp_in_r_max then
      signal.amp_in_r_max = signal.amp_in_r
    end
  end

  -- co-routine: input monitor
  input_level_poll_clock = clock.run(
    function()
      local step_s = 1 / 15
      while true do
        clock.sleep(step_s)
        repoll_input_level()
        if get_current_page_name() == "Input Level" then
          mark_screen_dirty()
        end
      end
  end)
end

function cleanup_input_level_poll()
  clock.cancel(input_level_poll_clock)
end


-- -------------------------------------------------------------------------
-- DRAW

function draw_input_uv_meter(value, maximum, offset)
  local viewport = { width = 128, height = 64 }
  local size = {width = 4, height = viewport.height - 4}
  local pos = {x = viewport.width - size.width - offset, y = 2}
  ratio = value / maximum
  activity = util.clamp(size.height - (ratio * size.height), 3, size.height)
  screen.line_width(size.width)

  screen.level(1)
  screen.move(pos.x,pos.y)
  screen.line(pos.x,pos.y + size.height)
  screen.stroke()
  screen.level(15)
  screen.move(pos.x,pos.y + size.height)
  screen.line(pos.x,activity)
  screen.stroke()
  screen.line_width(1)
end

function draw_input_levels()
  draw_input_uv_meter(signal.amp_in_l, signal.amp_in_l_max, 5)
  draw_input_uv_meter(signal.amp_in_r, signal.amp_in_r_max, 0)
end
