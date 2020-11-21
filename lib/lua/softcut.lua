--
-- SOFTCUT
--


-- -------------------------------------------------------------------------
-- STATE

local state = {
  recording = false,
  rec_time = 0,
}

function sofcut_get_record_duration()
  return state.rec_time
end


-- -------------------------------------------------------------------------
-- INIT / CLEANUP

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
  if state.recording then state.rec_time = x end
end


-- -------------------------------------------------------------------------
-- RECORD

--- Predicate, is curently recorded
function softcut_is_recording()
  return state.recording
end

--- Predicate, has something recorded
function softcut_has_recording()
  return state.rec_time ~= 0
end

--- Toggle Softcut record start / stop
function softcut_toggle_record()
  state.recording = not state.recording
  if state.recording then
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
    state.rec_time = 0
  end
end


-- -------------------------------------------------------------------------
-- PLAYBACK

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


-- -------------------------------------------------------------------------
-- PLAYBACK OPTIONS

--- Update current Softcut buffer playback speed
-- unused
sofcut_update_current_playback_rate = function()
  local n = rpmate.current_playback_ratio()
  for i=1, 2 do
    softcut.rate(0, n)
  end
end


-- -------------------------------------------------------------------------
-- SAVE TO DISK

function sofcut_write_to_file(filepath)
  softcut.buffer_write_stereo(filepath, 0, state.rec_time)
  -- softcut.buffer_write_stereo(filepath, 0, -1)
end
