--
-- screen_main
--


include('rpmate/lib/lua/math')
include('rpmate/lib/lua/devices')


-- -------------------------------------------------------------------------
-- STATE

-- devices connectors
local input_device_out_x = nil
local sampler_in_x = nil


-- -------------------------------------------------------------------------
-- INIT

function init_devices()
  norns_x = centered_x(norns_w)
  norns_in_x = norns_x + norns_in_rel_x
  norns_out_x = norns_x + norns_out_rel_x
end


-- -------------------------------------------------------------------------
-- EVENT LOOP


main_screen_enc = function(n, d)
  local op = 1
  if d < 0 then op = -1 end

  if is_shift_on() then
    if n == 1 then
      params:set("sampler_model", util.clamp(params:get("sampler_model") + op, 1, #sampler_device_list))
    end
  else
    if n == 2 then
      params:set("rec_speed", util.clamp(params:get("rec_speed") + op, 1, #rpm_hz_list))
      timber_update_current_playback_rate()
    elseif n == 3 then
      params:set("play_speed", util.clamp(params:get("play_speed") + op, 1, #rpm_hz_list))
      timber_update_current_playback_rate()
    end
  end

end

--- Main draw fn
draw_main_screen = function(in_speed_id, out_speed_id, sampler_id)
  draw_input_device(in_speed_id)
  draw_norns(out_speed_id)
  draw_sampler(sampler_id)
  draw_action()
  draw_speed_ratio(in_speed_id, out_speed_id)
end


-- -------------------------------------------------------------------------
-- DRAW: CURRENT ACTION

--- Draw recording icon
-- stateless
draw_action_rec = function()
  local r = 4
  local w = r * 2
  local x = centered_x(w) + r
  local y = 35
  screen.aa(1)
  screen.level(15)
  screen.move(x, y)
  screen.circle(x, y, r)
  screen.fill()
  screen.aa(0)
end

--- Draw waiting icon
-- stateless
draw_action_wait = function()
  local txt = "..."
  local w = screen.text_extents(txt)
  local x = centered_x(w)
  local y = 35
  screen.level(15)
  screen.move(x, y)
  screen.text(txt)
end

--- Draw playing icon
-- stateless
draw_action_play = function()
  local w = 8
  local h = 8
  local x = centered_x(w)
  local y = 35
  screen.aa(1)
  screen.level(15)
  screen.move(x, y - h / 2)
  screen.line_rel(0, h)
  screen.line_rel(w, - h / 2)
  screen.line(x, y - h / 2)
  screen.fill()
  screen.aa(0)
end

--- Draw corresponding icon if an action is being performed
draw_action = function()
  if timber_is_playing() then
    draw_action_play()
  elseif waiting then
    draw_action_wait()
  elseif softcut_is_recording() then
    draw_action_rec()
  end
end


-- -------------------------------------------------------------------------
-- DRAW: DEVICES

--- Draw device on screen
-- @param device hardware sampler name
-- @param x X position
-- @param y Y position
draw_device = function(device, x, y)
  screen.display_png("/home/we/dust/code/rpmate/rsc/devices/"..device..".png", x, y)
end

--- Draw connector (jack) at the back/front of device
-- @param x X position
-- @param y Y position
draw_connector = function(x, y)
  screen.level(3)
  screen.pixel(x-1, y)
  screen.pixel(x,   y)
  screen.pixel(x,   y-1)
  screen.pixel(x,   y-2)
  screen.pixel(x,   y-3)
  screen.close()
  screen.fill()
end

--- Draw current input (sound source) device
draw_input_device = function(record_speed)
  local device_id = record_speed
  local device = rpm_device_list[device_id]
  local w = rpm_device_w[device_id]
  local x = centered_x(w, (128 - norns_w) / 2)

  -- connector
  input_device_out_x = x + rpm_device_cnnx_rel_x[device_id]
  draw_connector(input_device_out_x, 19)

  -- wire towards norns
  screen.level(8)
  screen.line_width(1)
  screen.move(input_device_out_x, 16)
  screen.line(norns_in_x + 1, 16)
  screen.stroke()

  if device == "washing-machine" then
    draw_device(device, 0, rpm_device_y[device_id])
    -- screen.level(8)
    -- screen.move(0, 40)
    -- screen.text(rpm_label_list[device_id])
  else
    draw_device(device, x, rpm_device_y[device_id])

    local txt = rpm_label_list[device_id].."RPM"
    w = screen.text_extents(txt)
    x = centered_x(w, (128 - norns_w) / 2)
    screen.level(8)
    screen.move(x, 50)
    screen.text(txt)
  end
end

--- Draw norns device
draw_norns = function(playback_speed)
  local w = norns_w
  local x = norns_x

  draw_connector(norns_in_x, 19)
  draw_connector(norns_out_x, 19)
  draw_device("norns", norns_x, 20)

  local txt = rpm_label_list[playback_speed].."RPM"
  w = screen.text_extents(txt)
  x = centered_x(w)
  screen.level(8)
  screen.move(x, 50)
  screen.text(txt)
end

--- Draw current hardware sampler device
draw_sampler = function(device_id)
  local w = sampler_device_w[device_id]
  local x = 64 + centered_x(w, (128 + norns_w) / 2)

  local in_x = x + sampler_device_cnnx_rel_x[device_id]
  screen.line_width(1)
  screen.move(norns_out_x, 16)
  screen.line(in_x + 1, 16)
  screen.stroke()
  draw_connector(in_x, 19)
  draw_device(sampler_device_list[device_id], x, 20)

  local txt = sampler_label_list[device_id]
  w = screen.text_extents(txt)
  x = 64 + centered_x(w, (128 + norns_w) / 2)
  screen.level(8)
  screen.move(x, 50)
  screen.text(txt)
end

function draw_speed_ratio (record_speed, playback_speed)
  local in_hz = rpm_hz_list[record_speed]
  local out_hz = rpm_hz_list[playback_speed]
  local n = math.ceil(100 * out_hz / in_hz)

  local txt = n.."%"
  local w = screen.text_extents(txt)
  local x = centered_x(w)
  local y = 60
  screen.level(8)
  screen.move(x, y)
  screen.text(txt)
end
