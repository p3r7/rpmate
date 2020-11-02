--
-- RPMate 200926
-- @eigenbahn
-- llllllll.co/t/RPMate


-- -------------------------------------------------------------------------
-- VARS

local rpmate = {}

local ui_lib = require "ui"
local fileselect = require "fileselect"
local textentry = require "textentry"
local MusicUtil = require "musicutil"

local inspect = include('rpmate/lib/inspect')

local playing, recording, filesel, settings, mounted, blink = false, false, false, false, false, false
local speed, clip_length, rec_vol, input_vol, engine_vol, total_tracks, in_l, in_r = 0, 60, 1, 1, 0, 4, 0, 0

local rpm_hz_list    =  { 0.28, 0.55, 0.75, 1.3, 2.667, 8.667 }
local rpm_label_list =  { "16", "33", "45", "78", "160", "520" }
local rpm_device_list = { "tt-16", "tt-33", "tt-45", "tt-78", "edison-cylinder", "washing-machine" }
local rpm_device_w =    { 26, 26, 26, 26, 27, 26 }
local rpm_device_y =             { 20, 20, 20, 20, 10, 10 }
local rpm_device_cnnx_rel_x =    { 17, 17, 17, 17, 17, 17 }
local rpm_disk_d =      { 9, 12 , 7, 10 }

local input_device_out_x = nil
local norns_in_x = nil
local norns_out_x = nil
local sampler_in_x = nil

local norns_w = 14
local norns_in_rel_x = 6
local norns_out_rel_x = 9

local sampler_label_list =  { "MPC 2k", "S950", "SP-404" }
local sampler_device_list = { "mpc-2k_2", "s950", "sp-404" }
local sampler_device_w =    { 28, 33, 13 }
local sampler_device_cnnx_rel_x =    { 17, 22, 5 }


local tmp_record_folder = '/dev/shm/'..'rpmate_tmp/'

-- UI
local pages
local tabs
local tab_titles = {{"RPM"}, {"Cut"}, {"EQ"}, {"Dirty"}, {"HW Sampler Inst."}}
local eq_l_dial
local eq_m_dial
local eq_h_dial

local NUM_SAMPLES = 1 -- for timber init

local ui = {
  plate = {
    x = 20,
    y = 35,

    out_r = 15,
    in_r = 14,

    edge_l = 2,
    mat_l = 1,
    disk_l = 6,
  },
  arm = {
    delta_w_disk_edge = 3,
    length = 22,
    l = 0,
    base = {
      l = 1,
      r = 5,
    }
  }
}

local state = {
  record_speed = 2,
  playback_speed = 2,
  sampler = 1,

  -- rec
  rec = { arm = false, time = 0, start = 0, level = 1, pre = 1, threshold = 1 },

  -- track
  time = 0,
  s = 1,
  e = 1,
  level = 1,
}


-- -------------------------------------------------------------------------
-- TIMBER SC ENGINE

function unrequire(name)
  package.loaded[name] = nil
  _G[name] = nil
end

unrequire("timber/lib/timber_engine")
local Timber = include("timber/lib/timber_engine")
engine.name = "Timber"


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

function timber_play()
  local sample_id = 0
  local vel = 1
  engine.noteOn(sample_id, MusicUtil.note_num_to_freq(60), vel, sample_id)
end

function timber_stop()
  local sample_id = 0
  engine.noteOff(sample_id)
end

function timber_is_playing()
  local sample_id = 0
  return len(Timber.samples_meta[sample_id].positions) ~= 0
end

function timber_has_sample_loaded()
  return Timber.samples_meta[0].manual_load
end

function timber_free_up_sample()
  if timber_has_sample_loaded() then
    -- stop playing
    if timber_is_playing() then
      timber_stop()
    end

    -- clear previously set sample if any
    Timber.clear_samples(0, 0)
  end

end

-- -------------------------------------------------------------------------
-- CORE HELPERS

function len(T)
  local count = 0
  for _ in pairs(T) do count = count + 1 end
  return count
end


-- -------------------------------------------------------------------------
-- HELPERS

rpmate.update_rate = function(voice)
  local in_hz = rpm_hz_list[state.record_speed]
  local out_hz = rpm_hz_list[state.playback_speed]
  -- print("in_hz="..in_hz)
  -- print("out_hz="..out_hz)

  local n = out_hz / in_hz
  -- print("playback_speed="..n)

  -- if playing then softcut.rate(voice, n) end

  -- if state.rec.time ~= 0 then
  --   -- Timber.setArgOnSample(0, "pitchBendSampleRatio", 1)
  -- end
  -- if Timber.samples_meta[0].manual_load then
  params:set('by_percentage_'..0, n * 100)
  -- end
end


-- -------------------------------------------------------------------------
-- SOFTCUT

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

  softcut.event_phase(rpmate.phase)
  softcut.poll_start_phase()
end


-- NB: softcut event phase
rpmate.phase = function(voice, x)
  -- if playing then
  --   state.time = x
  -- end
  -- print("hello")
  if recording then state.rec.time = x end
end

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

function softcut_record_on()
  timber_free_up_sample()

  softcut_clear_buffers()
  for i=1, 2 do
    softcut.rec(i, 1)
  end
  -- state.rec.time = util.time()
end

function softcut_record_off()
  for i=1, 2 do
    softcut.rec(i, 0)
    softcut.position(i, 0)
  end
end

function softcut_clear_buffers()
  for i=1, 2 do
    softcut.buffer_clear(i)
    softcut.position(i, 0)
    state.rec.time = 0
  end
end

function softcut_play()
  for i=1, 2 do
    softcut.position(i, 0)
    softcut.play(i, 1)
  end
end

function softcut_stop()
  for i=1, 2 do
    softcut.position(i, 0)
    softcut.play(i, 0)
  end
end


-- -------------------------------------------------------------------------
-- SOFTCUT -> ENGINE PASSTHROUGH

function cut_to_engine()
  cutsample = tmp_record_folder.."buffer.wav"
  -- softcut.buffer_write_stereo(cutsample, 0, -1)
  softcut.buffer_write_stereo(cutsample, 0, state.rec.time)
  -- clock.sleep(2) -- or however you want to allow time to save/load
  load_sample_file_to_engine_timber(cutsample)
end

function load_sample_file_to_engine_timber(smpl)
  -- print(inspect(Timber.samples_meta[0]))
  -- timber_free_up_sample()
  Timber.load_sample(0, smpl)
  -- params:set('play_mode_' .. 0, 3)
end

function load_sample_file_to_engine_glut(smpl)
  params:set("1sample", smpl)
end


-- -------------------------------------------------------------------------
-- UTILS: SCREEN POSITION

rpmate.centered_x = function(w, max_w)
  if not max_w then
    max_w = 128
  end
  return math.floor((max_w - w) / 2)
end

rpmate.centered_y = function(h, max_h)
  if not max_h then
    max_h = 64
  end
  return math.floor((max_h - h) / 2)
end

-- -------------------------------------------------------------------------
-- UI: DEVICES

rpmate.draw_device = function(device, x, y)
  screen.display_png("/home/we/dust/code/rpmate/rsc/devices/"..device..".png", x, y)
end

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

rpmate.draw_input_device = function()
  local device = rpm_device_list[state.record_speed]
  local w = rpm_device_w[state.record_speed]
  local x = rpmate.centered_x(w, (128 - norns_w) / 2)

  input_device_out_x = x + rpm_device_cnnx_rel_x[state.sampler]
  rpmate.draw_connector(input_device_out_x, 19)

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

rpmate.draw_norns = function()
  local w = norns_w
  local x = rpmate.centered_x(w)

  norns_in_x = x + norns_in_rel_x
  norns_out_x = x + norns_out_rel_x

  screen.line_width(1)
  screen.move(input_device_out_x, 16)
  screen.line(norns_in_x + 1, 16)
  screen.stroke()

  rpmate.draw_connector(norns_in_x, 19)
  rpmate.draw_connector(norns_out_x, 19)
  rpmate.draw_device("norns", x, 20)

  local txt = rpm_label_list[state.playback_speed].."RPM"
  w = screen.text_extents(txt)
  x = rpmate.centered_x(w)
  screen.level(8)
  screen.move(x, 50)
  screen.text(txt)
end

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
-- UI: GENERAL

local function update_pages()
  tabs:set_index(1)
  tabs.titles = tab_titles[pages.index]
  -- env_status.text = ""
  -- update_tabs()
end

rpmate.draw_rpm = function()
  local x_k = 60
  local x_v = x_k + 20
  local y1 = 32
  local y2 = y1 + 7

  screen.level(1)

  screen.move(x_k, y1)
  screen.text("Rec:")
  screen.move(x_v, y1)
  screen.text(rpm_label_list[state.record_speed].."RPM")

  screen.move(x_k, y2)
  screen.text("Play:")
  screen.move(x_v, y2)
  screen.text(rpm_label_list[state.playback_speed].."RPM")
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

  rpmate.update_rate(voice)

  -- UI
  pages = ui_lib.Pages.new(1, len(tab_titles))
  tabs = ui_lib.Tabs.new(1, tab_titles[pages.index])

  -- eq_l_dial = UI.Dial.new(72, 19, 22, fm1_amount.actual * 100, 0, 100, 1)
  -- eq_m_dial = UI.Dial.new(72, 19, 22, fm1_amount.actual * 100, 0, 100, 1)
  -- eq_h_dial = UI.Dial.new(72, 19, 22, fm1_amount.actual * 100, 0, 100, 1)


  -- params:add_separator()
end


function rpmate:cleanup()
  poll:clear_all()
  print('cleanup')
end


-- -------------------------------------------------------------------------
-- STD API

function rpmate:key(n, z)
  -- print('key', n, z)

  if n == 2 and z == 0 then
    softcut_toggle_record()
  end
  if n == 3 and z == 0 then
    if not recording and state.rec.time ~= 0 then
      timber_toggle_play()
      -- timber_play()
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
    state.record_speed = util.clamp(state.record_speed + op, 1, len(rpm_hz_list))
  elseif n == 3 then
    -- 3: Playback Speed
    local op = 1
    if d < 0 then op = -1 end
    -- state.playback_speed = util.clamp(state.playback_speed + op, 1, len(rpm_hz_list))
    state.sampler = util.clamp(state.sampler + op, 1, len(sampler_device_list))
  end
  rpmate.update_rate()
  -- print('enc', n, d)

  rpmate:redraw()
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

    -- rpmate.draw_rpm()
  end

  screen.update()
end


-- -------------------------------------------------------------------------
-- RETURN MODULE

return rpmate
