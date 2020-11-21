--
-- screen_dirtying
--


include('rpmate/lib/lua/math')


-- -------------------------------------------------------------------------
-- EVENT LOOP

screen_dirtying_enc = function(n, d, timber)
  local op = 1
  if d < 0 then op = -1 end

  if is_shift_on() and n == 1 then
    params:set("quality_"..0, util.clamp(params:get("quality_"..0) + op, 1, len(timber.options.QUALITY)))
  elseif n == 2 then
    if is_shift_on() then op = 1000 * op end
    params:set("sample_rate_"..0, util.clamp(params:get("sample_rate_"..0) + op, 8000, 48000))
    timber_update_current_playback_rate()
  elseif n == 3 then
    if is_shift_on() then op = 2 * op end
    params:set("bit_depth_"..0, util.clamp(params:get("bit_depth_"..0) + op, 8, 24))
    timber_update_current_playback_rate()
  end

end

function draw_dirtying(timber)
  screen.level(8)

  local label_x = 20
  local value_x = 80

  screen.move(label_x, 30)
  screen.text("Preset:")
  screen.move(value_x, 30)
  screen.text(timber.options.QUALITY[params:get("quality_"..0)])

  screen.move(label_x, 40)
  screen.text("Sample Rate:")
  screen.move(value_x, 40)
  screen.text(params:get("sample_rate_"..0))

  screen.move(label_x, 50)
  screen.text("Bit Depth:")
  screen.move(value_x, 50)
  screen.text(params:get("bit_depth_"..0))
end
