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

local rpm_hz_list    = { 0.28, 0.55, 0.75, 1.3 }
local rpm_label_list = { "16", "33", "45", "78" }
local rpm_disk_d = { 9, 12 , 7, 10 }

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
    params:set('play_mode_' .. i, 4) -- "1-Shot" in options.PLAY_MODE_BUFFER
    --params:set('amp_env_sustain_' .. i, 0)
  end
end

function timber_toggle_play()
  playing = not playing
  if playing then
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
    softcut.level(i,1)
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
  if Timber.samples_meta[0].manual_load then
    -- clear previously set sample if any
    Timber.clear_samples(0, 1)
  end
  Timber.load_sample(0, smpl)
  -- print(inspect(Timber.samples_meta[0]))
end

function load_sample_file_to_engine_glut(smpl)
  params:set("1sample", smpl)
end


-- -------------------------------------------------------------------------
-- UI: TURNTABLE

rpmate.inches_to_scaled_px = function(v)
  return math.floor(v * ui.plate.in_r / 12)
end

rpmate.calculate_arm_head_x = function(arm_length, arm_base_x, arm_base_y, splindle_y, disk_r)
  -- basically, Pythagorean theorem applied
  -- arm_length = sqrt(y_rel² + x_rel²)
  -- => x_rel = sqrt(|arm_length² - y_rel²|)

  y_rel = (splindle_y - arm_base_y) + disk_r - ui.arm.delta_w_disk_edge
  print("y_rel="..y_rel)

  print("1: "..arm_length.." -> "..math.pow(arm_length, 2))
  print("2: "..y_rel.." -> "..(math.pow(y_rel, 2)))
  local x_rel = math.sqrt(math.pow(arm_length, 2) - math.pow(y_rel, 2))
  print("=> "..x_rel)
  return x_rel
end



rpmate.draw_bezier_test = function()
  local x = 50
  local y = 30
  screen.level(6)
  screen.line_width(1)
  screen.close()
  screen.move(x, y)
  -- screen.line_rel(0, 20)
  screen.curve_rel(5, 5, 10, 10, 0, 20)
  screen.stroke()
end

rpmate.draw_tt = function()

  local plate_edge_l = 2
  local plate_mat_l = 1
  local out_plate_r = 15
  local in_plate_r = 14
  local disk_r = rpmate.inches_to_scaled_px(rpm_disk_d[state.record_speed])
  local disk_l = 6

  local x = ui.plate.x
  local y = ui.plate.y

  -- arm base
  screen.level(ui.arm.base.l)
  local y_d = ui.plate.out_r - 6
  local arm_base_x = x + (ui.plate.out_r + 2)
  local arm_base_y = y - y_d, ui.arm.base.r
  screen.circle(arm_base_x, arm_base_y, ui.arm.base.r)
  screen.fill()

  -- disk_r

  -- plate
  screen.level(ui.plate.edge_l)
  screen.circle(x, y, ui.plate.out_r)
  screen.fill()
  screen.level(ui.plate.mat_l)
  screen.circle(x, y, ui.plate.in_r)
  screen.fill()
  -- record
  screen.level(ui.plate.disk_l)
  screen.circle(x, y, disk_r)
  screen.fill()
  -- splindle
  screen.level(2)
  screen.pixel(x, y)
  screen.fill()
  -- body
  screen.level(2)
  screen.line_width(1)
  screen.close()
  screen.move(x - (ui.plate.out_r + 3),  y - (ui.plate.out_r + 3))
  screen.line(x - (ui.plate.out_r + 3),  y + (ui.plate.out_r + 3))
  screen.move(x - (ui.plate.out_r + 3),  y + (ui.plate.out_r + 3))
  screen.line(x + (ui.plate.out_r + 10), y + (ui.plate.out_r + 2))
  screen.move(x + (ui.plate.out_r + 10), y + (ui.plate.out_r + 2))
  screen.line(x + (ui.plate.out_r + 10), y - (ui.plate.out_r + 2))
  screen.move(x + (ui.plate.out_r + 10), y - (ui.plate.out_r + 2))
  screen.line(x - (ui.plate.out_r + 3),  y - (ui.plate.out_r + 2))
  screen.stroke()
  -- speed selector
  -- screen.level(1)
  -- screen.line_width(1)
  -- screen.close()
  -- screen.move(x + (ui.plate.out_r + 10) - 7,  y + (ui.plate.out_r + 2) - 13)
  -- screen.line(x + (ui.plate.out_r + 10) - 4,  y + (ui.plate.out_r + 2) - 13)
  -- screen.move(x + (ui.plate.out_r + 10) - 4,  y + (ui.plate.out_r + 2) - 13)
  -- screen.line(x + (ui.plate.out_r + 10) - 4,  y + (ui.plate.out_r + 2) - 4)
  -- screen.move(x + (ui.plate.out_r + 10) - 4,  y + (ui.plate.out_r + 2) - 4)
  -- screen.line(x + (ui.plate.out_r + 10) - 7,  y + (ui.plate.out_r + 2) - 4)
  -- screen.move(x + (ui.plate.out_r + 10) - 7,  y + (ui.plate.out_r + 2) - 4)
  -- screen.line(x + (ui.plate.out_r + 10) - 7,  y + (ui.plate.out_r + 2) - 14)
  -- screen.stroke()


  -- arm
  arm_rel_x = rpmate.calculate_arm_head_x(ui.arm.length, arm_base_x, arm_base_y, y, disk_r)
  arm_abs_x = arm_base_x - arm_rel_x
  arm_abs_y = y + disk_r - ui.arm.delta_w_disk_edge
  arm_rel_y = (y - arm_base_y) + disk_r - ui.arm.delta_w_disk_edge

  screen.level(ui.arm.l)
  screen.line_width(1.9)
  screen.close()
  screen.move(arm_base_x, arm_base_y)
  print("From: ("..arm_base_x..","..arm_base_y..")")
  -- screen.line(arm_abs_x, arm_abs_y)
  screen.line_rel(-arm_rel_x, arm_rel_y)
  -- screen.curve_rel(-3, 15, 10, -10, -arm_rel_x, arm_rel_y)
  print("To: ("..arm_abs_x..","..arm_abs_y..")")
  screen.stroke()

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
      -- timber_toggle_play()
      timber_play()
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
    state.playback_speed = util.clamp(state.playback_speed + op, 1, len(rpm_hz_list))
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
    rpmate.draw_tt()
    -- rpmate.draw_bezier_test()
    rpmate.draw_rpm()
  end

  screen.update()
end


-- -------------------------------------------------------------------------
-- RETURN MODULE

return rpmate
