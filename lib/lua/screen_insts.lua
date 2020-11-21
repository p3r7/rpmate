--
-- screen_insts
--
-- HW SAMPLER INSTRUCTIONS PAGE


include('rpmate/lib/lua/math')
include('rpmate/lib/lua/devices')


-- -------------------------------------------------------------------------
-- EVENT LOOP

insts_screen_enc = function(n, d)
  local op = 1
  if d < 0 then op = -1 end

  if n == 2 then
    params:set("rec_speed", util.clamp(params:get("rec_speed") + op, 1, #rpm_hz_list))
    timber_update_current_playback_rate()
  elseif n == 3 then
    params:set("play_speed", util.clamp(params:get("play_speed") + op, 1, #rpm_hz_list))
    timber_update_current_playback_rate()
  end
end

function draw_instructions(device_id, record_speed, playback_speed)
  local sampler = sampler_label_list[device_id]
  if sampler == "MPC 2k" then
    draw_instructions_mpc(record_speed, playback_speed)
  elseif sampler == "S950" then
    draw_instructions_s950(record_speed, playback_speed)
  elseif sampler == "SP-404" then
    draw_instructions_sp404(record_speed, playback_speed)
  else
    -- not supported yet
    print("not supported yet")
  end
end


-- -------------------------------------------------------------------------
-- DRAW

function draw_instructions_generic(record_speed, playback_speed, menu_line_1, menu_line_2, params_line, menu_line_2_shift)
  screen.level(8)

  if not menu_line_2_shift then
    menu_line_2_shift = 0
  end

  local x = 10
  local y = 20
  local txt = rpm_label_list[record_speed].."RPM".." <- "..rpm_label_list[playback_speed].."RPM"
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

function draw_instructions_mpc(record_speed, playback_speed)
  local in_hz = rpm_hz_list[record_speed]
  local out_hz = rpm_hz_list[playback_speed]
  local semitones = playback_speed_to_semitones(out_hz / in_hz)
  local tunes = semitones_to_mpc_tune(semitones)
  draw_instructions_generic(
    record_speed, playback_speed,
    "In Program > Parameter",
    "> TUNING",
    "TUNE: "..tunes,
    51
  )
end

function draw_instructions_s950(record_speed, playback_speed)
  local in_hz = rpm_hz_list[record_speed]
  local out_hz = rpm_hz_list[playback_speed]
  local semitones = playback_speed_to_semitones(out_hz / in_hz)
  local semitones_label = math.ceil(semitones)
  if semitones_label < 0 then
    semitones_label = "- "..(-1 * semitones_label)
  else
    semitones_label = "+ "..semitones_label
  end
  draw_instructions_generic(
    record_speed, playback_speed,
    "In EDIT SAMPLE > Page 03",
    "",
    "#Nom Pitch: "..semitones_label,
    51
  )
end

function draw_instructions_sp404(record_speed, playback_speed)
  draw_instructions_generic(
    record_speed, playback_speed,
    "Hit BPM button,",
    " turn BPM CONTROL knob",
    ""
  )

end
