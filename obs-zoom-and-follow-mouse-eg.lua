obs = obslua
ffi = require("ffi")

-- Constants
local SCRIPT_NAME = "OBS - Zoom and Follow Mouse - EG"
local CROP_FILTER_NAME = "ObsZoomAndFollowCropEg"
local VERSION = "0.1.0"

-- Global variables
local zoom_source = ""
local zoom_filter = nil
local hotkey_zoom_id = obs.OBS_INVALID_HOTKEY_ID
local hotkey_follow_id = obs.OBS_INVALID_HOTKEY_ID
local zoom_active = false
local follow_active = true
local zoom_width = 1280
local zoom_height = 720
local active_border = 0.15
local max_speed = 160
local smooth_factor = 1.0
local zoom_duration = 300
local manual_offset = false
local manual_x_offset = 0
local manual_y_offset = 0
local debug_logging = false

local source_width = 0
local source_height = 0
local zoom_x = 0
local zoom_y = 0
local zoom_x_target = 0
local zoom_y_target = 0
local is_zooming = false
local zoom_start_time = 0

-- Platform-specific mouse position functions
local get_mouse_pos
if ffi.os == "Windows" then
    ffi.cdef[[
        typedef struct {
            long x;
            long y;
        } POINT;
        int GetCursorPos(POINT* lpPoint);
    ]]
    local point = ffi.new("POINT[1]")
    function get_mouse_pos()
        ffi.C.GetCursorPos(point)
        return point[0].x, point[0].y
    end
elseif ffi.os == "Linux" then
    ffi.cdef[[
        typedef struct {
            long x;
            long y;
        } XPoint;
        typedef unsigned long Window;
        typedef struct _XDisplay Display;
        Display* XOpenDisplay(const char* display_name);
        int XQueryPointer(Display* display, Window w, Window* root_return, Window* child_return, int* root_x_return, int* root_y_return, int* win_x_return, int* win_y_return, unsigned int* mask_return);
        int XCloseDisplay(Display* display);
    ]]
    local x11 = ffi.load("X11")
    local display = x11.XOpenDisplay(nil)
    local root_window = x11.XDefaultRootWindow(display)
    local root_x = ffi.new("int[1]")
    local root_y = ffi.new("int[1]")
    function get_mouse_pos()
        x11.XQueryPointer(display, root_window, nil, nil, root_x, root_y, nil, nil, nil)
        return root_x[0], root_y[0]
    end
elseif ffi.os == "OSX" then
    ffi.cdef[[
        typedef struct {
            double x;
            double y;
        } CGPoint;
        CGPoint CGEventGetLocation(void* event);
        void* CGEventCreate(void* source);
        void CFRelease(void* cf);
    ]]
    local core_graphics = ffi.load("CoreGraphics", true)
    function get_mouse_pos()
        local event = core_graphics.CGEventCreate(nil)
        local point = core_graphics.CGEventGetLocation(event)
        core_graphics.CFRelease(event)
        return math.floor(point.x), math.floor(point.y)
    end
else
    function get_mouse_pos()
        log("Unsupported operating system for mouse position")
        return 0, 0
    end
end

-- Utility functions
local function log(message)
    if debug_logging then
        print(message)
    end
end

local function get_source_by_name(name)
    local source = obs.obs_get_source_by_name(name)
    if source ~= nil then
        obs.obs_source_release(source)
    end
    return source
end

local function create_filter(source, filter_name, filter_type, settings)
    local filter = obs.obs_source_get_filter_by_name(source, filter_name)
    if filter == nil then
        filter = obs.obs_source_create_private(filter_type, filter_name, settings)
        obs.obs_source_filter_add(source, filter)
    end
    obs.obs_source_release(filter)
    return filter
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function distance(x1, y1, x2, y2)
    return math.sqrt((x2 - x1)^2 + (y2 - y1)^2)
end

local function get_source_info(source)
    if source == nil then
        return
    end

    source_width = obs.obs_source_get_width(source)
    source_height = obs.obs_source_get_height(source)
end

local function update_crop_filter()
    if zoom_source == "" then
        return
    end

    local source = obs.obs_get_source_by_name(zoom_source)
    if source == nil then
        return
    end

    local filter = obs.obs_source_get_filter_by_name(source, CROP_FILTER_NAME)
    if filter == nil then
        local settings = obs.obs_data_create()
        filter = create_filter(source, CROP_FILTER_NAME, "crop_filter", settings)
        obs.obs_data_release(settings)
    end

    local settings = obs.obs_source_get_settings(filter)
    obs.obs_data_set_int(settings, "left", math.floor(zoom_x))
    obs.obs_data_set_int(settings, "top", math.floor(zoom_y))
    obs.obs_data_set_int(settings, "right", math.floor(source_width - zoom_width - zoom_x))
    obs.obs_data_set_int(settings, "bottom", math.floor(source_height - zoom_height - zoom_y))
    obs.obs_source_update(filter, settings)
    obs.obs_data_release(settings)

    obs.obs_source_release(filter)
    obs.obs_source_release(source)
end

local function update_zoom()
    if zoom_source == "" or (not zoom_active and not is_zooming) then
        return
    end

    local source = obs.obs_get_source_by_name(zoom_source)
    if source == nil then
        return
    end

    get_source_info(source)
    set_initial_bounding_box(source)

    local mouse_x, mouse_y = get_mouse_pos()
    
    if manual_offset then
        mouse_x = mouse_x - manual_x_offset
        mouse_y = mouse_y - manual_y_offset
    end

    mouse_x = math.max(0, math.min(mouse_x, source_width))
    mouse_y = math.max(0, math.min(mouse_y, source_height))

    if is_zooming then
        local target_x = math.max(0, math.min(mouse_x - zoom_width / 2, source_width - zoom_width))
        local target_y = math.max(0, math.min(mouse_y - zoom_height / 2, source_height - zoom_height))

        if follow_active then
            local dist = distance(zoom_x, zoom_y, target_x, target_y)
            local max_dist = math.min(zoom_width, zoom_height) * active_border

            if dist > max_dist then
                local angle = math.atan2(target_y - zoom_y, target_x - zoom_x)
                zoom_x_target = zoom_x + math.cos(angle) * (dist - max_dist)
                zoom_y_target = zoom_y + math.sin(angle) * (dist - max_dist)
            else
                zoom_x_target = zoom_x
                zoom_y_target = zoom_y
            end
        else
            zoom_x_target = target_x
            zoom_y_target = target_y
        end
    else
        zoom_x_target = 0
        zoom_y_target = 0
    end

    local t = math.min((obs.os_gettime_ns() / 1000000 - zoom_start_time) / zoom_duration, 1)
    t = t * t * (3 - 2 * t)  -- Smooth step interpolation

    local speed = smooth_factor > 0 and distance(zoom_x, zoom_y, zoom_x_target, zoom_y_target) / smooth_factor or 0
    speed = math.min(speed, max_speed)

    zoom_x = lerp(zoom_x, zoom_x_target, speed * t)
    zoom_y = lerp(zoom_y, zoom_y_target, speed * t)

    local new_zoom_x = lerp(zoom_x, zoom_x_target, speed * t)
    local new_zoom_y = lerp(zoom_y, zoom_y_target, speed * t)
    
    if math.abs(new_zoom_x - zoom_x) > 0.1 or math.abs(new_zoom_y - zoom_y) > 0.1 then
        zoom_x = new_zoom_x
        zoom_y = new_zoom_y
        update_crop_filter()
    end

    obs.obs_source_release(source)
end

-- Callback functions for hotkeys
local function on_zoom_hotkey(pressed)
    if pressed then
        if zoom_active then
            is_zooming = false
        else
            is_zooming = true
        end
        zoom_active = not zoom_active
        zoom_start_time = obs.os_gettime_ns() / 1000000
        log("Zoom: " .. tostring(zoom_active))
    end
end

local function on_follow_hotkey(pressed)
    if pressed then
        follow_active = not follow_active
        log("Follow: " .. tostring(follow_active))
    end
end

-- OBS script functions
function script_description()
    return "Crops and resizes a source to simulate a zoomed in view tracked to the mouse. " ..
           "Set activation hotkey in Settings. Version " .. VERSION
end

function script_properties()
    local props = obs.obs_properties_create()

    local source_list = obs.obs_properties_add_list(props, "zoom_source", "Zoom Source", obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING)
    local sources = obs.obs_enum_sources()
    if sources ~= nil then
        for _, source in ipairs(sources) do
            local name = obs.obs_source_get_name(source)
            local id = obs.obs_source_get_id(source)
            if id == "monitor_capture" or id == "window_capture" or id == "game_capture" or id == "xshm_input" or id == "screen_capture" then
                obs.obs_property_list_add_string(source_list, name, name)
            end
        end
    end
    obs.source_list_release(sources)

    obs.obs_properties_add_int(props, "zoom_width", "Zoom Window Width", 320, 3840, 1)
    obs.obs_properties_add_int(props, "zoom_height", "Zoom Window Height", 240, 2160, 1)
    obs.obs_properties_add_float_slider(props, "active_border", "Active Border", 0, 0.5, 0.01)
    obs.obs_properties_add_int(props, "max_speed", "Max Scroll Speed", 0, 540, 10)
    obs.obs_properties_add_float_slider(props, "smooth_factor", "Smooth Factor", 0.1, 10, 0.1)
    obs.obs_properties_add_int_slider(props, "zoom_duration", "Zoom Duration (ms)", 0, 1000, 1)

    local manual_offset_prop = obs.obs_properties_add_bool(props, "manual_offset", "Enable Manual Offset")
    local manual_x_offset_prop = obs.obs_properties_add_int(props, "manual_x_offset", "Manual X Offset", -8000, 8000, 1)
    local manual_y_offset_prop = obs.obs_properties_add_int(props, "manual_y_offset", "Manual Y Offset", -8000, 8000, 1)

    obs.obs_properties_add_bool(props, "debug_logging", "Enable debug logging")

    -- Set visibility callbacks
    obs.obs_property_set_modified_callback(manual_offset_prop, function(props, property, settings)
        local enabled = obs.obs_data_get_bool(settings, "manual_offset")
        obs.obs_property_set_visible(manual_x_offset_prop, enabled)
        obs.obs_property_set_visible(manual_y_offset_prop, enabled)
        return true
    end)

    return props
end

function script_update(settings)
    zoom_source = obs.obs_data_get_string(settings, "zoom_source")
    zoom_width = obs.obs_data_get_int(settings, "zoom_width")
    zoom_height = obs.obs_data_get_int(settings, "zoom_height")
    active_border = obs.obs_data_get_double(settings, "active_border")
    max_speed = obs.obs_data_get_int(settings, "max_speed")
    smooth_factor = obs.obs_data_get_double(settings, "smooth_factor")
    zoom_duration = obs.obs_data_get_int(settings, "zoom_duration")
    
    manual_offset = obs.obs_data_get_bool(settings, "manual_offset")
    manual_x_offset = obs.obs_data_get_int(settings, "manual_x_offset")
    manual_y_offset = obs.obs_data_get_int(settings, "manual_y_offset")
    
    debug_logging = obs.obs_data_get_bool(settings, "debug_logging")

    -- Update source info
    local source = obs.obs_get_source_by_name(zoom_source)
    if source ~= nil then
        get_source_info(source)
        obs.obs_source_release(source)
    end
end

function script_load(settings)
    hotkey_zoom_id = obs.obs_hotkey_register_frontend("zoom_and_follow.zoom.toggle", "Toggle Zoom", on_zoom_hotkey)
    hotkey_follow_id = obs.obs_hotkey_register_frontend("zoom_and_follow.follow.toggle", "Toggle Follow", on_follow_hotkey)

    local hotkey_save_array = obs.obs_data_get_array(settings, "zoom_and_follow.zoom.toggle")
    obs.obs_hotkey_load(hotkey_zoom_id, hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)

    hotkey_save_array = obs.obs_data_get_array(settings, "zoom_and_follow.follow.toggle")
    obs.obs_hotkey_load(hotkey_follow_id, hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)

    -- Register callbacks
    local sh = obs.obs_get_signal_handler()
    obs.signal_handler_connect(sh, "source_rename", on_source_rename)
    obs.signal_handler_connect(sh, "source_remove", on_source_remove)
    obs.obs_frontend_add_event_callback(function(event)
        if event == obs.OBS_FRONTEND_EVENT_SCENE_CHANGED then
            on_scene_change()
        end
    end)
end

function script_save(settings)
    local hotkey_save_array = obs.obs_hotkey_save(hotkey_zoom_id)
    obs.obs_data_set_array(settings, "zoom_and_follow.zoom.toggle", hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)

    hotkey_save_array = obs.obs_hotkey_save(hotkey_follow_id)
    obs.obs_data_set_array(settings, "zoom_and_follow.follow.toggle", hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)
end

function script_unload()
    obs.obs_hotkey_unregister(on_zoom_hotkey)
    obs.obs_hotkey_unregister(on_follow_hotkey)

    -- Unregister callbacks
    local sh = obs.obs_get_signal_handler()
    obs.signal_handler_disconnect(sh, "source_rename", on_source_rename)
    obs.signal_handler_disconnect(sh, "source_remove", on_source_remove)
    obs.obs_frontend_remove_event_callback(on_scene_change)
end

function script_tick(seconds)
    if zoom_active or is_zooming then
        local success, error_message = pcall(update_zoom)
        if not success then
            log("Errore in update_zoom: " .. tostring(error_message))
            -- Resetta lo zoom in caso di errore
            reset_zoom()
        end
    end
end

-- Helper function to create the initial bounding box for the source
local function set_initial_bounding_box(source)
    local scene = obs.obs_scene_from_source(obs.obs_frontend_get_current_scene())
    if scene and source then
        local sceneitem = obs.obs_scene_find_source(scene, obs.obs_source_get_name(source))
        if sceneitem then
            if obs.obs_sceneitem_get_bounds_type(sceneitem) == obs.OBS_BOUNDS_NONE then
                obs.obs_sceneitem_set_bounds_type(sceneitem, obs.OBS_BOUNDS_SCALE_INNER)
                obs.obs_sceneitem_set_bounds_alignment(sceneitem, 0)
                local video_info = obs.obs_video_info()
                if obs.obs_get_video_info(video_info) then
                    local bounds = obs.vec2()
                    bounds.x = video_info.base_width
                    bounds.y = video_info.base_height
                    obs.obs_sceneitem_set_bounds(sceneitem, bounds)
                end
            end
        end
        obs.obs_scene_release(scene)
    end
end

-- Add a function to reset the zoom when changing scenes or sources
local function reset_zoom()
    if not zoom_active and not is_zooming and zoom_x == 0 and zoom_y == 0 then
        return
    end
    zoom_active = false
    is_zooming = false
    zoom_x = 0
    zoom_y = 0
    zoom_x_target = 0
    zoom_y_target = 0
    update_crop_filter()
end

-- Add callbacks for scene and source changes
local function on_scene_change(scene)
    reset_zoom()
end

local function on_source_rename(source_name, new_name)
    if source_name == zoom_source then
        zoom_source = new_name
    end
end

local function on_source_remove(calldata)
    local source = obs.calldata_source(calldata, "source")
    if source ~= nil then
        local name = obs.obs_source_get_name(source)
        if name == zoom_source then
            reset_zoom()
            zoom_source = ""
        end
    end
end