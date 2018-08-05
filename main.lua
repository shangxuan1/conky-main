--[[
Boolean conventions:
  0 is true, 1 is false

Module format:
  LIBRARY STRUCTURE (a collection of functions/values in a table):
    local M = {}  -- define module-level table to return

    local modname = requires 'modname'
    -- import all required modules

    local foo = function()
      -- code
    end

    -- define more functions

    M.foo = foo -- dump all functions into table

    return M  -- return entire table (use functions as modname.foo)

  RENDERING MODULE STRUCTURE (only used in this module; main.lua):
    local modname = requires 'modname'
    -- import all required modules

    local foo = function()
      -- code
    end

    local draw = function(args)
       -- drawing code that uses foo()
    end

    return draw -- only draw is returned (use as modname(args))

Var names:
  - delimiters: all words separated by _ (unless camalCase)
  - booleans: preceed by is_ (as in is_awesome)
  - Spacial scope:
    - Everything declared local by default
    - reassigning to local:
      - upval to local: prefix with _
      - global to local: prefix with __
      - replace . with _ if callng from table
      - the only reason to do either of these is for performance, therefore
        no need to localize variables that are only used during init
    - global: preceed with g_
  - Temporal Scope
    - init: only relevent to startup (nil'ed before first rendering loop)
    - persistant: always relevent (potentially)
    - flank init vars with _
  - Mutability
    - variable: lowercase
    - constant: ALL_CAPS
    - constants can be anything except functions
  - Module Names:
    - CapCamalCase
    - var name is exactly the same as module name
--]]
local UPDATE_FREQUENCY = 1						--Hz

_G_INIT_DATA_ = {
	UPDATE_INTERVAL 	= 1 / UPDATE_FREQUENCY,
	
	LEFT_X 				= 32,
	SECTION_WIDTH		= 436,
	CENTER_PAD 			= 20,
	PANEL_HORZ_SPACING 	= 10,
	PANEL_MARGIN_X		= 20,
	PANEL_MARGIN_Y		= 10,
	
	TOP_Y				= 21,
	SIDE_HEIGHT 		= 1020,
	CENTER_HEIGHT 		= 220,

	-- silly hack, the price of a litewait language
	ABS_PATH			= debug.getinfo(1).source:match("@?(.*/)")
}

_G_INIT_DATA_.CENTER_LEFT_X = _G_INIT_DATA_.LEFT_X + _G_INIT_DATA_.SECTION_WIDTH + _G_INIT_DATA_.PANEL_MARGIN_X * 2 + _G_INIT_DATA_.PANEL_HORZ_SPACING
_G_INIT_DATA_.CENTER_RIGHT_X = _G_INIT_DATA_.CENTER_LEFT_X + _G_INIT_DATA_.SECTION_WIDTH + _G_INIT_DATA_.CENTER_PAD
_G_INIT_DATA_.CENTER_WIDTH = _G_INIT_DATA_.SECTION_WIDTH * 2 + _G_INIT_DATA_.CENTER_PAD
_G_INIT_DATA_.RIGHT_X = _G_INIT_DATA_.CENTER_LEFT_X + _G_INIT_DATA_.CENTER_WIDTH + _G_INIT_DATA_.PANEL_MARGIN_X * 2 + _G_INIT_DATA_.PANEL_HORZ_SPACING

package.path = _G_INIT_DATA_.ABS_PATH..'/?.lua;'..
  _G_INIT_DATA_.ABS_PATH..'/drawing/?.lua;'..
  _G_INIT_DATA_.ABS_PATH..'/schema/?.lua;'..
  _G_INIT_DATA_.ABS_PATH..'/core/func/?.lua;'..
  _G_INIT_DATA_.ABS_PATH..'/core/super/?.lua;'..
  _G_INIT_DATA_.ABS_PATH..'/core/widget/?.lua;'..
  _G_INIT_DATA_.ABS_PATH..'/core/widget/arc/?.lua;'..
  _G_INIT_DATA_.ABS_PATH..'/core/widget/text/?.lua;'..
  _G_INIT_DATA_.ABS_PATH..'/core/widget/plot/?.lua;'..
  _G_INIT_DATA_.ABS_PATH..'/core/widget/rect/?.lua;'..
  _G_INIT_DATA_.ABS_PATH..'/core/widget/poly/?.lua;'..
  _G_INIT_DATA_.ABS_PATH..'/core/widget/image/?.lua;'

conky_set_update_interval(_G_INIT_DATA_.UPDATE_INTERVAL)

require 'cairo'

_G_Widget_ 		= require 'Widget'
_G_Patterns_ 	= require 'Patterns'

local Util 			= require 'Util'
local Panel 		= require 'Panel'
local System 		= require 'System'
local Network 		= require 'Network'
local Processor 	= require 'Processor'
local FileSystem 	= require 'FileSystem'
local Pacman 		= require 'Pacman'
local Power 		= require 'Power'
local ReadWrite		= require 'ReadWrite'
local Graphics		= require 'Graphics'
local Memory		= require 'Memory'

local _unrequire = function(m) package.loaded[m] = nil end

_G_Widget_ = nil
_G_Patterns_ = nil

_unrequire('Super')
_unrequire('Color')
_unrequire('Gradient')
_unrequire('Widget')
_unrequire('Patterns')

_unrequire = nil

_G_INIT_DATA_ = nil

local updates = -2

local __cairo_xlib_surface_create 	= cairo_xlib_surface_create
local __cairo_create 				= cairo_create
local __cairo_surface_destroy 		= cairo_surface_destroy
local __cairo_destroy 				= cairo_destroy
local __collectgarbage				= collectgarbage

local using_ac = function()
	return Util.conky('${acpiacadapter AC}') == 'on-line'
end

local current_last_log_entry = Util.execute_cmd('tail -1 /var/log/pacman.log')

local check_if_log_changed = function()
	local new_last_log_entry = Util.execute_cmd('tail -1 /var/log/pacman.log')
	if new_last_log_entry == current_last_log_entry then return 1 end
	current_last_log_entry = new_last_log_entry
	return 0
end

-- kept for historic reasons, if we choose to make another panel then this
-- will be useful
local current_interface = 0

local cs_p
local uninit = 1

conky_startup = function()
   cs_p = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 1920, 1080)
   local cr = __cairo_create(cs_p)
   Panel(cr)
   uninit = nil
end

function conky_main()
   if uninit then return end
   local _cw = conky_window
   if not _cw then return end
   local cs = __cairo_xlib_surface_create(_cw.display, _cw.drawable, _cw.visual, 1920, 1080)
   local cr = __cairo_create(cs)
   
   cairo_set_source_surface(cr, cs_p, 0, 0)
   cairo_paint(cr)
   
   updates = updates + 1
   
   local t1 = updates % (UPDATE_FREQUENCY * 10)
   
   local t2
   local is_using_ac = using_ac()
   if is_using_ac then
	  t2 = updates % (UPDATE_FREQUENCY * 60)
   else
	  t2 = updates % (UPDATE_FREQUENCY * 300)
   end
   
   local log_is_changed = false
   if t2 == 0 then log_is_changed = check_if_log_changed() end
   
   -- local pt1 = os.clock()
   
   System(cr, current_interface, log_is_changed)
   Graphics(cr, current_interface)
   Processor(cr, current_interface)
   
   ReadWrite(cr, current_interface, UPDATE_FREQUENCY)
   Network(cr, current_interface, UPDATE_FREQUENCY)
   
   Pacman(cr, current_interface, log_is_changed)
   FileSystem(cr, current_interface, t1)
   Power(cr, current_interface, UPDATE_FREQUENCY, is_using_ac)
   Memory(cr, current_interface)
   
   -- local pt2 = os.clock() - pt1
   -- print(pt2)
   
   __cairo_surface_destroy(cs)
   __cairo_destroy(cr)
   __collectgarbage()
end
