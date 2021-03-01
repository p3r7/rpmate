--
-- rpmate.
---
-- @eigen
-- llllllll.co/t/RPMate


-- TODO:
-- - fine playback speed VS % pitch (up to -/+16, like on a turntable)
-- - hw sampler instructions: pitch ratio (half/quarter...)
-- - digital input gain w/ visualization


-- -------------------------------------------------------------------------
-- IMPORTS

local inspect = include('lib/inspect')

include('lib/lua/io')
include('lib/lua/ui')

include('lib/lua/math')
include('lib/lua/softcut') -- record
timber_wrapper = include('lib/lua/timber')  -- playback

include('lib/lua/screen_main')
include('lib/lua/screen_insts')
include('lib/lua/screen_input_level')
include('lib/lua/screen_dirtying')


-- -------------------------------------------------------------------------
-- MODULE VAR

local rpmate = {}


-- -------------------------------------------------------------------------
-- CONSTANTS

-- tmp buffer file
local tmp_record_folder = '/dev/shm/'..'rpmate_tmp/'
-- local tmp_record_folder = '/home/we/dust/audio/'..'rpmate_tmp/'


-- -------------------------------------------------------------------------
-- STATE: FUNCTIONAL

-- params
local input_vol = 1
local rec_vol = 1
local level = 1

local waiting = false


-- -------------------------------------------------------------------------
-- CURRENT PLAYBACK RATIO STATE

--- Get current playback ratio
rpmate.current_playback_ratio = function()
  local in_hz = rpm_hz_list[params:get("rec_speed")]
  local out_hz = rpm_hz_list[params:get("play_speed")]
  return out_hz / in_hz
end

rpmate.get_current_semitones_shift = function()
  local n = rpmate.current_playback_ratio()
  return playback_speed_to_semitones(n)
end


--- Update current Timber sample playback speed
timber_update_current_playback_rate = function()
  local n = rpmate.current_playback_ratio()
  timber_update_playback_rate(n)
end


-- -------------------------------------------------------------------------
-- SOFTCUT -> ENGINE PASSTHROUGH

--- Load Softcut buffer into Timber
-- Uses a temporary file
function cut_to_engine()
  local cutsample = tmp_record_folder.."buffer.wav"
  clock.run(function()
      waiting = true
      sofcut_write_to_file(cutsample)
      clock.sleep(0.2) -- wait a bit to prevent race condition
      timber_load_sample(cutsample)
      timber_update_current_playback_rate()

      waiting = false
      mark_screen_dirty()
  end)
end


-- -------------------------------------------------------------------------
-- INIT / CLEANUP

rpmate.init = function()

  -- tmp recording storage
  if not util.file_exists(tmp_record_folder) then util.make_dir(tmp_record_folder) end

  audio.rev_off()

  params:add_separator()
  params:add_separator("rpmate")

  params:add_option("rec_speed", "Record speed:", rpm_label_list, 2)
  params:add_option("play_speed", "Playback speed:", rpm_label_list, 2)
  params:add_option("sampler_model", "Sampler Model:", sampler_label_list, 1)

  -- params:add_separator()
  -- params:add_control("IN", "Input level", controlspec.new(0, 1, 'lin', 0, 1, ""))
  -- params:set_action("IN", function(x) input_vol = x  audio.level_adc_cut(input_vol) end)
  -- params:add_separator()

  -- params:add_control("vol", "Volume", controlspec.new(0, 1, 'lin', 0, 1, ""))
  -- params:set_action("vol",
  --                   function(x)
  --                     level = x
  --                     softcut.level(voice, level)
  -- end)

  -- params:add_control("pan", "Pan", controlspec.new(-1, 1, 'lin', 0, 0, ""))
  -- params:set_action("pan", function(x) softcut.pan(voice, x) end)

  softcut_init()

  timber_init()
  timber_update_current_playback_rate()

  ui_init()
  init_screen_redraw()
  init_input_level_poll()
  init_devices()

end


function rpmate:cleanup()
  audio.rev_on()

  poll:clear_all()

  cleanup_screen_redraw()
  cleanup_input_level_poll()
  timber_cleanup()

  print('cleanup')
end


-- -------------------------------------------------------------------------
-- STD API

function rpmate:key(n, z)
  if n == 1 then
    if z == 1 then
      shift_on()
    else
      shift_off()
    end
  end

  local current_page_id = get_current_page()

  if current_page_id == 1 then
    if n == 2 and z == 0 then
      softcut_toggle_record()
      mark_screen_dirty()
    end

    if n == 3 and z == 0 then
      print("attempt to play")
      print("recording: "..tostring(softcut_is_recording()))
      print("record duration: "..sofcut_get_record_duration())

      if not softcut_is_recording() and softcut_has_recording() then
        timber_toggle_play()
        mark_screen_dirty()
      end
    end
  end

end

function rpmate:enc(n, d)
  norns.encoders.set_sens(1, 7)
  norns.encoders.set_sens(2, 5)
  norns.encoders.set_sens(3, 5)
  norns.encoders.set_accel(1, false)
  norns.encoders.set_accel(2, false)
  norns.encoders.set_accel(3, false)

  if not is_shift_on() and n == 1 then
    -- 1: Record Volume
    -- rec_vol = util.clamp(rec_vol + d / 100, 0, 1)
    -- mix:set_raw("monitor", rec_vol)
    -- audio.level_adc_cut(rec_vol)
    -- softcut.rec_level(sel, rec_vol)

    -- 1: Page scroll
    ui_update_pages(d)
  else
    local current_page = get_current_page_name()
    if current_page == "RPMate" then
      main_screen_enc(n, d)
    elseif current_page == "HW Sampler Inst." then
      insts_screen_enc(n, d)
    elseif current_page == "Dirtying" then
      screen_dirtying_enc(n, d, timber_wrapper.timber)
    end
  end
  -- print('enc', n, d)

  mark_screen_dirty()
end

function rpmate:redraw()
  -- print('redraw')
  screen.clear()

  ui_redraw()

  local current_page = get_current_page_name()
  if current_page == "RPMate" then
    draw_main_screen(params:get("rec_speed"), params:get("play_speed"), params:get("sampler_model"))
  elseif current_page == "HW Sampler Inst." then
    draw_instructions(params:get("sampler_model"), params:get("rec_speed"), params:get("play_speed"))
  elseif current_page == "Input Level" then
    draw_input_levels()
  elseif current_page == "Dirtying" then
    draw_dirtying(timber_wrapper.timber)
  end

  screen.update()
end


-- -------------------------------------------------------------------------
-- RETURN MODULE

return rpmate
