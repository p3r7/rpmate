--
-- TIMBER SC ENGINE
--


local MusicUtil = require "musicutil"

include('rpmate/lib/lua/core')
include('rpmate/lib/lua/io')

unrequire("rpmate/lib/timbereq_engine")
local Timber = include("rpmate/lib/timbereq_engine")
engine.name = "TimberEq"


-- -------------------------------------------------------------------------
-- CONSTANTS

local NUM_SAMPLES = 1


-- -------------------------------------------------------------------------
-- STATE

local timber_wrapper = {}
timber_wrapper.timber = Timber

local timber_was_playing = false

local playback_check_ps = 30
local playback_check_clock


-- -------------------------------------------------------------------------
-- INIT / CLEANUP

--- Timber Engine init phase
function timber_init()
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

  -- co-routine: playback change of state check
  playback_check_clock = clock.run(
    function()
      local step_s = 1 / playback_check_ps
      while true do
        clock.sleep(step_s)
        local is_playing = timber_is_playing()
        if is_playing ~= timber_was_playing then
          mark_screen_dirty()
        end
        timber_was_playing = is_playing
      end
  end)
end

function timber_cleanup()
  clock.cancel(playback_check_clock)
end


-- -------------------------------------------------------------------------
-- LOAD / UNLOAD SAMPLE

--- Predicate, has Timber a sample loaded?
function timber_has_sample_loaded()
  return Timber.samples_meta[0].manual_load
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


-- -------------------------------------------------------------------------
-- PLAY SAMPLE

--- Predicate, is Timber playing the sample?
function timber_is_playing()
  local sample_id = 0
  -- REVIEW: '#' shorthand for length doesn't appear to work
  return len(Timber.samples_meta[sample_id].positions) ~= 0
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


-- -------------------------------------------------------------------------
-- SAMPLE OPTIONS

--- Update Timber sample playback speed
timber_update_playback_rate = function(rate)
  params:set('by_percentage_'..0, rate * 100)
end


-- -------------------------------------------------------------------------
-- return

return timber_wrapper
