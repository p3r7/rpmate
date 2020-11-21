--
-- math
--


-- -------------------------------------------------------------------------
-- GENERIC

function log2(v)
  return math.log(v) / math.log(2)
end


-- -------------------------------------------------------------------------
-- SCREEN POSITIONING

--- Calculate centered position of element onto surface, accordinf to 1 dimension
-- pure function
-- @param v element size
-- @param max surface size
function centered(v, max)
  return math.floor((max - v) / 2)
end

--- Calculate centered x position of element onto surface
-- pure function
-- @param w element width
-- @param max_w surface width, defaults to 128
function centered_x(w, max_w)
  if not max_w then
    max_w = 128
  end
  return centered(w, max_w)
end

--- Calculate centered y position of element onto surface
-- pure function
-- @param h element height
-- @param max_h surface height, defaults to 64
function centered_y(h, max_h)
  if not max_h then
    max_h = 64
  end
  return centered(h, max_h)
end


-- -------------------------------------------------------------------------
-- RATE / PITCH

--- Converts semitones shift to corresponding playback speed
-- pure function
-- @param semitones number of semitones shifted
-- @param divisions number of semitones division (in an octave), defaults to 12
function semitones_to_playback_speed(semitones, divisions)
  if not divisions then
     divisions = 12
  end
  return 2 ^ (semitones / divisions)
end

--- Converts playback speed to corresponding semitones shift
-- pure function
-- @param playback_speed ratio playback_speed/record_speed, between 0..1 (not %-normalized)
-- @param divisions number of semitones division (in an octave), defaults to 12
function playback_speed_to_semitones(playback_speed, divisions)
  if not divisions then
     divisions = 12
  end
  return divisions * log2(playback_speed)
end


-- -------------------------------------------------------------------------
-- RATE / PITCH: SAMPLER-SPECIFIC

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

--- Converts semitones to MPC "TUNE" unit
-- 1 semitone is roughly 10 MPC "TUNEs"
-- @param semitones number of semitones shift induced by playback speed
function semitones_to_mpc_tune (semitones)
  return math.ceil(semitones * 9.675)
end
