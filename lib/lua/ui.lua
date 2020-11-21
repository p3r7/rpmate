--
-- ui
--
-- Standard UI components (pages / dials...)


local ui_lib = require "ui"


-- -------------------------------------------------------------------------
-- STATE

local pages = nil
local tabs = nil
local tab_titles = {
  {"RPMate"},
  {"HW Sampler Inst."},
  -- {"Input Level"},
  {"Dirtying"},
  -- {"EQ"},
}

-- dials
local eq_l_dial = nil
local eq_m_dial = nil
local eq_h_dial = nil


-- -------------------------------------------------------------------------
-- INIT / CLEANUP

function ui_init()
  pages = ui_lib.Pages.new(1, #tab_titles)
  tabs = ui_lib.Tabs.new(1, tab_titles[pages.index])

  -- eq_l_dial = UI.Dial.new(72, 19, 22, fm1_amount.actual * 100, 0, 100, 1)
  -- eq_m_dial = UI.Dial.new(72, 19, 22, fm1_amount.actual * 100, 0, 100, 1)
  -- eq_h_dial = UI.Dial.new(72, 19, 22, fm1_amount.actual * 100, 0, 100, 1)
end


-- -------------------------------------------------------------------------
-- STANDARD LOOP

function ui_redraw()
  pages:redraw()
  tabs:redraw()
end


-- -------------------------------------------------------------------------
-- ACCESSORS

function get_current_page()
  return pages.index
end

function get_current_page_name()
  return tab_titles[pages.index][1]
end

-- -------------------------------------------------------------------------
-- INTERACTIONS

--- Update pages/tabs
function ui_update_pages(delta)
  pages:set_index_delta(util.clamp(delta, -1, 1), false)

  tabs:set_index(1)
  tabs.titles = tab_titles[pages.index]
  -- env_status.text = ""
  -- update_tabs()
end
