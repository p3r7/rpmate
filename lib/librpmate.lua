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

-- local math = require "math"
local ui_lib = require "ui"
local textentry = require "textentry"
local MusicUtil = require "musicutil"

local inspect = include('rpmate/lib/inspect')


-- -------------------------------------------------------------------------
-- MODULE VAR

local rpmate = {}


-- -------------------------------------------------------------------------
-- CONSTANTS

-- Timber
local NUM_SAMPLES = 1

-- tmp buffer file
local tmp_record_folder = '/dev/shm/'..'rpmate_tmp/'
-- local tmp_record_folder = '/home/we/dust/audio/'..'rpmate_tmp/'

-- record / playback speeds
local rpm_hz_list    =  { 0.28, 0.55, 0.75, 1.3, 2.667, 8.667 }
local rpm_label_list =  { "16", "33", "45", "78", "160", "520" }

-- devices: input
local rpm_device_list = { "tt-16", "tt-33", "tt-45", "tt-78", "edison-cylinder", "washing-machine" }
local rpm_device_w =    { 26, 26, 26, 26, 27, 100 }
local rpm_device_y =             { 20, 20, 20, 20, 10, 10 }
local rpm_device_cnnx_rel_x =    { 17, 17, 17, 17, 17, 0 }
local rpm_device_cnnx_rel_y =    { 0, 0, 0, 0, 20, 0 }

-- device: norns
local norns_w = 14
local norns_in_rel_x = 6
local norns_out_rel_x = 9
local norns_x = nil
local norns_in_x = nil
local norns_out_x = nil


-- devices: hw samplers
local sampler_label_list =  { "MPC 2k", "S950", "SP-404" }
local sampler_device_list = { "mpc-2k_2", "s950", "sp-404" }
local sampler_device_w =    { 28, 33, 13 }
local sampler_device_cnnx_rel_x =    { 17, 22, 5 }


-- -------------------------------------------------------------------------
-- STATE: I/O

local shift = false
local screen_dirty = false


-- -------------------------------------------------------------------------
-- STATE: UI

local pages
local tabs
local tab_titles = {{"RPMate"}, {"HW Sampler Inst."}, {"Cut"}, {"EQ"}, {"Dirty"}}
local eq_l_dial
local eq_m_dial
local eq_h_dial

-- devices connectors
local input_device_out_x = nil
local sampler_in_x = nil


-- -------------------------------------------------------------------------
-- STATE: FUNCTIONAL

local playing, recording = false, false
local speed, clip_length, rec_vol, input_vol, engine_vol, total_tracks, in_l, in_r = 0, 60, 1, 1, 0, 4, 0, 0

local speed_recovery = 0

local waiting = false
local timber_was_playing = false

local state = {
  record_speed = 2,
  playback_speed = 2,
  sampler = 1,

  -- rec
  rec = { time = 0 },

  -- track
  time = 0,
  level = 1,
}


-- MPC instructions:
--
-- TUNE 10 ~= 1 semitone
-- not exactly correct as:
--  - 33RPM -> 45RPM: 12 * log2(45/33) = 5.369 and not 5.1
--  - 33RPM -> 78RPM: 12 * log2(78/33) = 14.89 and not 14.4
--
-- in fact: MPC semitones = ceil(real semitones * 9.675)
--
-- 33RPM -> 45RPM:
--  - TUNE -51
--  - +16% PITCH - TUNE -78
--    12 * log2((45+(16*45/100))/33) = 7.93
-- 33RPM -> 78RPM:
--  - TUNE -144
--  - -16% PITCH - TUNE -116
--    12 * log2((78-(16*78/100))/33) = 11.873




-- -------------------------------------------------------------------------
-- CORE HELPERS

function unrequire(name)
  package.loaded[name] = nil
  _G[name] = nil
end

function len(T)
  local count = 0
  for _ in pairs(T) do count = count + 1 end
  return count
end


-- -------------------------------------------------------------------------
-- MATH: SPEED, RATE, PITCH

rpmate.log2 = function(v)
  return math.log(v) / math.log(2)
end

--- Converts semitones shift to corresponding playback speed
-- pure function
-- @param semitones number of semitones shifted
-- @param divisions number of semitones division (in an octave), defaults to 12
rpmate.semitones_to_playback_speed = function(semitones, divisions)
  if not divisions then
    divisions = 12
  end
  return 2 ^ (semitones / divisions)
end

--- Converts playback speed to corresponding semitones shift
-- pure function
-- @param playback_speed ratio playback_speed/record_speed, between 0..1 (not %-normalized)
-- @param divisions number of semitones division (in an octave), defaults to 12
rpmate.playback_speed_to_semitones = function(playback_speed, divisions)
  if not divisions then
    divisions = 12
  end
  return divisions * rpmate.log2(playback_speed)
end


-- -------------------------------------------------------------------------
-- MATH: HW SAMPLER-SPECIFIC

--- Converts semitones to MPC "TUNE" unit
-- 1 semitone is roughly 10 MPC "TUNEs"
-- @param semitones number of semitones shift induced by playback speed
rpmate.semitones_to_mpc_tune = function(semitones)
  return math.ceil(semitones * 9.675)
end


-- -------------------------------------------------------------------------
-- CURRENT PLAYBACK RATIO STATE

--- Get current playback ratio
rpmate.current_playback_ratio = function()
  local in_hz = rpm_hz_list[state.record_speed]
  local out_hz = rpm_hz_list[state.playback_speed]
  return out_hz / in_hz
end

rpmate.get_current_semitones_shift = function()
  local n = rpmate.current_playback_ratio()
  return rpmate.playback_speed_to_semitones(n)
end


-- -------------------------------------------------------------------------
-- TIMBER SC ENGINE

unrequire("rpmate/lib/timbereq_engine")
local Timber = include("rpmate/lib/timbereq_engine")
engine.name = "TimberEq"


--- Timber Engine init phase
function engine_init_timber()
  -- params:add_trigger('load_f','+ Load Folder')
  -- params:set_action('load_f', function() Timber.FileSelect.enter(_path.audio, function(file)
  --                                                                  if file ~= "cancel" then orca_engine.load_folder(file, add) end end) end)

  Timber.options.PLAY_MODE_BUFFER_DEFAULT = 3
  Timber.options.PLAY_MODE_STREAMING_DEFAULT = 3
  params:add_separator()
  Timber.add_params()
  for i = 0, NUM_SAMPLES - 1 do
    local extra_params = {
      {type = "option", id = "launch_mode_" .. i, name = "Launch Mode", options = {"Gate", "Toggle"}, default = 1, action = function(value)
         Timber.setup_params_dirty = true
      end},
    }
    params:add_separator()
    Timber.add_sample_params(i, true, extra_params)
    params:set('play_mode_' .. i, 3) -- "1-Shot" in options.PLAY_MODE_BUFFER
    --params:set('amp_env_sustain_' .. i, 0)
  end
end

--- Load sample file into Timber
-- @param smpl pth to sample on disk
function timber_load_sample(smpl)
  timber_free_up_sample()
  params:set('sample_'..0, smpl)

  -- NB: not working as expected:
  -- Timber.load_sample(0, smpl)
  -- params:set('play_mode_' .. 0, 3)
end

--- Toggle playback of currently loaded sample
function timber_toggle_play()
  playing = timber_is_playing()
  if not playing then
    print("play")
    timber_play()
  else
    print("stop")
    timber_stop()
  end
end

--- Play currently loaded sample
function timber_play()
  local sample_id = 0
  local vel = 1
  engine.noteOn(sample_id, MusicUtil.note_num_to_freq(60), vel, sample_id)
end

--- Stop playing currently loaded sample
function timber_stop()
  local sample_id = 0
  engine.noteOff(sample_id)
end

--- Predicate, is Timber playing the sample?
function timber_is_playing()
  local sample_id = 0
  -- REVIEW: '#' shorthand for length doesn't appear to work
  return len(Timber.samples_meta[sample_id].positions) ~= 0
end

--- Predicate, has Timber a sample loaded?
function timber_has_sample_loaded()
  return Timber.samples_meta[0].manual_load
end

--- If applicable, stop playing the sample and unload it
function timber_free_up_sample()
  if timber_has_sample_loaded() then
    -- stop playing
    if timber_is_playing() then
      timber_stop()
    end
  end

  -- clear previously set sample if any
  -- Timber.clear_samples(0, 0) -- NB: not working as expected
  params:set('clear_'..0, true)
end

--- Update current Timber sample playback speed
timber_update_current_playback_rate = function()
  local n = rpmate.current_playback_ratio()
  params:set('by_percentage_'..0, n * 100)
end


-- -------------------------------------------------------------------------
-- SOFTCUT

--- Softcut init phase
function softcut_init()
  softcut.reset()

  audio.level_cut(1.0)
  audio.level_adc_cut(1.0) -- listen analog input
  audio.level_eng_cut(0.0) -- don't listen engine / sc

  for i=1, 2 do
    softcut.level(i, 1.0)
    softcut.level_slew_time(i, 0.1)
    softcut.play(i, 0)
    softcut.rate(i, 1)
    softcut.rate_slew_time(i, 0.1)
    softcut.loop_start(i, 0)
    softcut.loop_end(i, 350)
    softcut.loop(i, 1)
    softcut.fade_time(i, 0.1)
    softcut.rec(i, 0)
    softcut.rec_level(i, 1)
    softcut.pre_level(i, 1)
    softcut.position(i, 0)
    softcut.buffer(i, i)
    softcut.enable(i, 1)
    softcut.filter_dry(i, 1)
    softcut.phase_quant(i, .01)
  end
  softcut.level_input_cut(1, 1, 1.0)
  softcut.level_input_cut(2, 1, 0.0)
  softcut.level_input_cut(1, 2, 0.0)
  softcut.level_input_cut(2, 2, 1.0)
  softcut.pan(1, -1.0)
  softcut.pan(2, 1.0)

  softcut.event_phase(softcut_event_phase)
  softcut.poll_start_phase()
end


--- Softcut event phase
-- @param voice current softcut voice
-- @param x time since record / playback
softcut_event_phase = function(voice, x)
  -- if playing then
  --   state.time = x
  -- end
  -- print("hello")
  if recording then state.rec.time = x end
end

--- Toggle Softcut record start / stop
function softcut_toggle_record()
  recording = not recording
  if recording then
    print("record on")
    softcut_record_on()
  else
    print("record off")
    softcut_record_off()
    cut_to_engine()
  end
end

--- Start Softcut record in buffer
function softcut_record_on()
  timber_free_up_sample()

  softcut_clear_buffers()
  for i=1, 2 do
    softcut.rec(i, 1)
  end
  -- state.rec.time = util.time()
end

--- Stop Softcut record in buffer
function softcut_record_off()
  for i=1, 2 do
    softcut.rec(i, 0)
    softcut.position(i, 0)
  end
end

--- Clear Softcut buffers
function softcut_clear_buffers()
  for i=1, 2 do
    softcut.buffer_clear(i)
    softcut.position(i, 0)
    state.rec.time = 0
  end
end

--- Play Softcut voices (mapped to buffers)
-- unused
function softcut_play()
  for i=1, 2 do
    softcut.position(i, 0)
    softcut.play(i, 1)
  end
end

--- Stop playing Softcut voices (mapped to buffers)
-- unused
function softcut_stop()
  for i=1, 2 do
    softcut.position(i, 0)
    softcut.play(i, 0)
  end
end

--- Update current Softcut buffer playback speed
-- unused
sofcut_update_current_playback_rate = function()
  local n = rpmate.current_playback_ratio()
  for i=1, 2 do
    softcut.rate(0, n)
  end
end


-- -------------------------------------------------------------------------
-- SOFTCUT -> ENGINE PASSTHROUGH

--- Load Softcut buffer into Timber
-- Uses a temporary file
function cut_to_engine()
  local cutsample = tmp_record_folder.."buffer.wav"
  clock.run(function()
      waiting = true

      -- softcut.buffer_write_stereo(cutsample, 0, -1)
      softcut.buffer_write_stereo(cutsample, 0, state.rec.time)
      clock.sleep(0.2) -- wait a bit to prevent race condition
      timber_load_sample(cutsample)
      timber_update_current_playback_rate()

      waiting = false
      screen_dirty = true
  end)
end



-- -------------------------------------------------------------------------
-- UTILS: SCREEN POSITION

--- Calculate centered x position of element onto surface
-- pure function
-- @param w element width
-- @param max_w surface width, defaults to 128
rpmate.centered_x = function(w, max_w)
  if not max_w then
    max_w = 128
  end
  return math.floor((max_w - w) / 2)
end

--- Calculate centered y position of element onto surface
-- pure function
-- @param h element height
-- @param max_h surface height, defaults to 64
rpmate.centered_y = function(h, max_h)
  if not max_h then
    max_h = 64
  end
  return math.floor((max_h - h) / 2)
end


-- -------------------------------------------------------------------------
-- UI: PAGES

--- Update pages/tabs
local function update_pages()
  tabs:set_index(1)
  tabs.titles = tab_titles[pages.index]
  -- env_status.text = ""
  -- update_tabs()
end


-- -------------------------------------------------------------------------
-- UI: MAIN PAGE (ACTIONS)

--- Draw recording icon
-- stateless
rpmate.draw_action_rec = function()
  local r = 4
  local w = r * 2
  local x = rpmate.centered_x(w) + r
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
rpmate.draw_action_wait = function()
  local txt = "..."
  local w = screen.text_extents(txt)
  local x = rpmate.centered_x(w)
  local y = 35
  screen.level(15)
  screen.move(x, y)
  screen.text(txt)
end

--- Draw playing icon
-- stateless
rpmate.draw_action_play = function()
  local w = 8
  local h = 8
  local x = rpmate.centered_x(w)
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
rpmate.draw_action = function()
  if timber_is_playing() then
    rpmate.draw_action_play()
  elseif waiting then
    rpmate.draw_action_wait()
  elseif recording then
    rpmate.draw_action_rec()
  end
end


-- -------------------------------------------------------------------------
-- UI: MAIN PAGE (DEVICES)

--- Draw device on screen
-- @param device hardware sampler name
-- @param x X position
-- @param y Y position
rpmate.draw_device = function(device, x, y)
  screen.display_png("/home/we/dust/code/rpmate/rsc/devices/"..device..".png", x, y)
end

--- Draw connector (jack) at the back/front of device
-- @param x X position
-- @param y Y position
rpmate.draw_connector = function(x, y)
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
rpmate.draw_input_device = function()
  local device = rpm_device_list[state.record_speed]
  local w = rpm_device_w[state.record_speed]
  local x = rpmate.centered_x(w, (128 - norns_w) / 2)

  -- connector
  input_device_out_x = x + rpm_device_cnnx_rel_x[state.sampler]
  rpmate.draw_connector(input_device_out_x, 19)

  -- wire towards norns
  screen.level(8)
  screen.line_width(1)
  screen.move(input_device_out_x, 16)
  screen.line(norns_in_x + 1, 16)
  screen.stroke()

  if device == "washing-machine" then
    rpmate.draw_device(device, 0, rpm_device_y[state.record_speed])
    -- screen.level(8)
    -- screen.move(0, 40)
    -- screen.text(rpm_label_list[state.record_speed])
  else
    rpmate.draw_device(device, x, rpm_device_y[state.record_speed])

    local txt = rpm_label_list[state.record_speed].."RPM"
    w = screen.text_extents(txt)
    x = rpmate.centered_x(w, (128 - norns_w) / 2)
    screen.level(8)
    screen.move(x, 50)
    screen.text(txt)
  end
end

--- Draw norns device
rpmate.draw_norns = function()
  local w = norns_w
  local x = norns_x

  rpmate.draw_connector(norns_in_x, 19)
  rpmate.draw_connector(norns_out_x, 19)
  rpmate.draw_device("norns", norns_x, 20)

  local txt = rpm_label_list[state.playback_speed].."RPM"
  w = screen.text_extents(txt)
  x = rpmate.centered_x(w)
  screen.level(8)
  screen.move(x, 50)
  screen.text(txt)
end

--- Draw current hardware sampler device
rpmate.draw_sampler = function()
  local w = sampler_device_w[state.sampler]
  local x = 64 + rpmate.centered_x(w, (128 + norns_w) / 2)

  local in_x = x + sampler_device_cnnx_rel_x[state.sampler]
  screen.line_width(1)
  screen.move(norns_out_x, 16)
  screen.line(in_x + 1, 16)
  screen.stroke()
  rpmate.draw_connector(in_x, 19)
  rpmate.draw_device(sampler_device_list[state.sampler], x, 20)

  local txt = sampler_label_list[state.sampler]
  w = screen.text_extents(txt)
  x = 64 + rpmate.centered_x(w, (128 + norns_w) / 2)
  screen.level(8)
  screen.move(x, 50)
  screen.text(txt)
end


-- -------------------------------------------------------------------------
-- UI: HW SAMPLER INSTRUCTIONS PAGE

rpmate.draw_instructions_generic = function(menu_line_1, menu_line_2, params_line, menu_line_2_shift)
  screen.level(8)

  if not menu_line_2_shift then
    menu_line_2_shift = 0
  end

  local x = 10
  local y = 20
  local txt = rpm_label_list[state.record_speed].."RPM".." <- "..rpm_label_list[state.playback_speed].."RPM"
  screen.move(x, y)
  screen.text(txt)

  y = 30
  txt = menu_line_1
  screen.move(x, y)
  screen.text(txt)

  x = x + menu_line_2_shift
  y = 40
  txt = menu_line_2
  screen.move(x, y)
  screen.text(txt)

  x = 10
  y = 50
  txt = params_line
  screen.move(x, y)
  screen.text(txt)

end

rpmate.draw_instructions_mpc = function()
  local semitones = rpmate.get_current_semitones_shift()
  local tunes = rpmate.semitones_to_mpc_tune(semitones)
  rpmate.draw_instructions_generic(
    "In Program > Parameter",
    "> TUNING",
    "TUNE: "..tunes,
    51
  )
end

rpmate.draw_instructions_sp404 = function()
  rpmate.draw_instructions_generic(
    "Hit BPM button,",
    " turn BPM CONTROL knob",
    ""
  )

end

rpmate.draw_instructions = function()
  local sampler = sampler_device_list[state.sampler]
  if sampler == "mpc-2k_2" then
    rpmate.draw_instructions_mpc()
  elseif sampler == "sp-404" then
    rpmate.draw_instructions_sp404()
  else
    -- not supported yet
    print("not supported yet")
  end
end

-- -------------------------------------------------------------------------
-- INIT / CLEANUP

rpmate.init = function()

  -- tmp recording storage
  if not util.file_exists(tmp_record_folder) then util.make_dir(tmp_record_folder) end



  params:add_separator()
  params:add_separator("rpmate")

  params:add_option ( "in_speed", "Record speed:", rpm_label_list, 1 )
  params:add_option ( "in_speed", "Playback speed:", rpm_label_list, 1 )
  params:add_separator()
  params:add_control("IN", "Input level", controlspec.new(0, 1, 'lin', 0, 1, ""))
  params:set_action("IN", function(x) input_vol = x  audio.level_adc_cut(input_vol) end)
  -- params:add_control("ENG", "Engine level", controlspec.new(0, 1, 'lin', 0, 0, ""))
  -- params:set_action("ENG", function(x) engine_vol = x audio.level_eng_cut(engine_vol) end)
  params:add_separator()

  params:add_control("vol", "Volume", controlspec.new(0, 1, 'lin', 0, 1, ""))
  params:set_action("vol",
                    function(x)
                      state.level = x
                      softcut.level(voice, state.level)
                      -- state.update_params_list()
  end)

  params:add_control("pan", "Pan", controlspec.new(-1, 1, 'lin', 0, 0, ""))
  params:set_action("pan", function(x) softcut.pan(voice, x) end)

  softcut_init()
  engine_init_timber()


  local vu_l, vu_r = poll.set("amp_in_l"), poll.set("amp_in_r")
  vu_l.time, vu_r.time = 1 / 30, 1 / 30
  vu_l.callback = function(val) in_l = val * 100 end
  vu_r.callback = function(val) in_r = val * 100 end
  vu_l:start()
  vu_r:start()

  timber_update_current_playback_rate()

  -- UI
  pages = ui_lib.Pages.new(1, #tab_titles)
  tabs = ui_lib.Tabs.new(1, tab_titles[pages.index])

  -- eq_l_dial = UI.Dial.new(72, 19, 22, fm1_amount.actual * 100, 0, 100, 1)
  -- eq_m_dial = UI.Dial.new(72, 19, 22, fm1_amount.actual * 100, 0, 100, 1)
  -- eq_h_dial = UI.Dial.new(72, 19, 22, fm1_amount.actual * 100, 0, 100, 1)

  norns_x = rpmate.centered_x(norns_w)
  norns_in_x = norns_x + norns_in_rel_x
  norns_out_x = norns_x + norns_out_rel_x

  -- params:add_separator()

  -- co-routine: screen redraw
  local redraw_fps = 30
  clock.run(
    function()
      local step_s = 1 / redraw_fps
      while true do
        clock.sleep(step_s)
        if screen_dirty then
          rpmate:redraw()
          screen_dirty = false
        end
      end
  end)

  -- co-routine: playback state check
  clock.run(
    function()
      local step_s = 1 / redraw_fps
      while true do
        clock.sleep(step_s)
        local is_playing = timber_is_playing()
        if is_playing ~= timber_was_playing then
          screen_dirty = true
        end
        timber_was_playing = is_playing
      end
  end)


end


function rpmate:cleanup()
  poll:clear_all()
  print('cleanup')
end


-- -------------------------------------------------------------------------
-- STD API

function rpmate:key(n, z)
  if n == 1 then
    if z == 1 then
      shift = true
    else
      shift = false
    end
  end

  if n == 2 and z == 0 then
    softcut_toggle_record()
    screen_dirty = true
  end

  if n == 3 and z == 0 then
    print("attempt to play")
    print("recording: "..tostring(recording))
    print("record duration: "..state.rec.time)

    if not recording and state.rec.time ~= 0 then
      timber_toggle_play()
      -- timber_play()
      screen_dirty = true
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

  if n == 1 then
    -- 1: Record Volume
    -- rec_vol = util.clamp(rec_vol + d / 100, 0, 1)
    -- mix:set_raw("monitor", rec_vol)
    -- audio.level_adc_cut(rec_vol)
    -- softcut.rec_level(sel, rec_vol)

    -- 1: Page scroll
    pages:set_index_delta(util.clamp(d, -1, 1), false)
    update_pages()
  elseif n == 2 then
    -- 3: Record Speed
    local op = 1
    if d < 0 then op = -1 end
    state.record_speed = util.clamp(state.record_speed + op, 1, #rpm_hz_list)
    timber_update_current_playback_rate()
  elseif n == 3 then
    local op = 1
    if d < 0 then op = -1 end
    if not shift then
      -- 3: Playback Speed
      state.playback_speed = util.clamp(state.playback_speed + op, 1, #rpm_hz_list)
      timber_update_current_playback_rate()
    elseif pages.index == 1 then
      -- Shift+3: HW Sampler Model
      state.sampler = util.clamp(state.sampler + op, 1, #sampler_device_list)
    end
  end
  -- print('enc', n, d)

  screen_dirty = true
end

function rpmate:redraw()
  -- print('redraw')
  screen.clear()

  pages:redraw()
  tabs:redraw()

  if pages.index == 1 then
    rpmate.draw_input_device()
    rpmate.draw_norns()
    rpmate.draw_sampler()

    rpmate.draw_action()
  elseif pages.index == 2 then
    rpmate.draw_instructions()
  end

  screen.update()
end


-- -------------------------------------------------------------------------
-- RETURN MODULE

return rpmate
