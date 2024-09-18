local obs = obslua
local ffi = require("ffi")

-- Costanti
local VERSION = "0.5.6"
local ZOOM_NAME_TOG = "zoom_and_follow.zoom.toggle"
local FOLLOW_NAME_TOG = "zoom_and_follow.follow.toggle"
local ZOOM_DESC_TOG = "Attiva/Disattiva Zoom Mouse"
local FOLLOW_DESC_TOG = "Attiva/Disattiva Segui Mouse"
local CROP_FILTER_NAME = "zoom-and-follow-crop"

-- Variabili globali
local zoom_active = false
local follow_active = false
local zoom_value = 2.0
local zoom_speed = 0.1
local follow_speed = 0.1
local debug_logging = false
local panic_mode = false

local source_name = ""
local source = nil
local crop_filter = nil
local original_crop = nil
local current_crop = nil
local zoom_target = nil
local zoom_center = nil
local zoom_in_progress = false
local zoom_target_reached = false

local hotkey_zoom_id = obs.OBS_INVALID_HOTKEY_ID
local hotkey_follow_id = obs.OBS_INVALID_HOTKEY_ID

local default_source_name = ""

local update_timer = nil

local base_width = 1920
local base_height = 1080
local use_custom_base_resolution = false

-- Funzioni di utilità
local function log(message)
    if debug_logging then
        print("[Zoom and Follow] " .. message)
    end
end

local function error_log(message)
    obs.script_log(obs.LOG_ERROR, "[Zoom and Follow ERROR] " .. message)
end

local function safe_call(func, ...)
    if not func then
        error_log("Tentativo di chiamare una funzione nulla")
        return nil
    end
    local status, result = pcall(func, ...)
    if not status then
        error_log("Errore durante l'esecuzione di una funzione: " .. tostring(result))
        return nil
    end
    return result
end

local function safe_release(obj)
    if obj then
        obs.obs_source_release(obj)
    end
end

local function reset_script_state()
    zoom_active = false
    follow_active = false
    source_name = ""
    safe_release(source)
    source = nil
    safe_release(crop_filter)
    crop_filter = nil
    original_crop = nil
    current_crop = nil
    zoom_target = nil
    zoom_center = nil
    if update_timer then
        obs.timer_remove(update_timer)
        update_timer = nil
    end
    panic_mode = false
end

local function get_monitor_info()
    log("Inizio della funzione get_monitor_info()")
    if ffi.os == "Windows" then
        ffi.cdef[[
            typedef unsigned long DWORD;
            typedef void* HANDLE;
            typedef HANDLE HMONITOR;
            typedef HANDLE HDC;
            typedef long LONG;
            typedef int BOOL;
            typedef long LPARAM;
            typedef struct {
                LONG left;
                LONG top;
                LONG right;
                LONG bottom;
            } RECT;
            typedef struct {
                DWORD cbSize;
                RECT  rcMonitor;
                RECT  rcWork;
                DWORD dwFlags;
            } MONITORINFO;
            typedef BOOL (*MONITORENUMPROC)(HMONITOR, HDC, RECT*, LPARAM);
            BOOL EnumDisplayMonitors(HDC, const RECT*, MONITORENUMPROC, LPARAM);
            BOOL GetMonitorInfoA(HMONITOR, MONITORINFO*);
        ]]
        
        local monitors = {}
        local function enum_callback(hMonitor, _, _, _)
            local mi = ffi.new("MONITORINFO")
            mi.cbSize = ffi.sizeof(mi)
            if ffi.C.GetMonitorInfoA(hMonitor, mi) then
                table.insert(monitors, {
                    left = mi.rcMonitor.left,
                    top = mi.rcMonitor.top,
                    right = mi.rcMonitor.right,
                    bottom = mi.rcMonitor.bottom
                })
            end
            return true
        end
        
        local callback = ffi.cast("MONITORENUMPROC", enum_callback)
        if ffi.C.EnumDisplayMonitors(nil, nil, callback, 0) then
            log(string.format("Numero di monitor rilevati: %d", #monitors))
            callback:free()
            return monitors
        else
            callback:free()
            error_log("Errore durante l'enumerazione dei monitor")
            return nil
        end
    else
        log("Sistema operativo non supportato, utilizzo dei valori di default per il monitor")
        return {{left = 0, top = 0, right = 1920, bottom = 1080}}
    end
end

local function get_mouse_pos()
    log("Inizio della funzione get_mouse_pos()")
    if ffi.os == "Windows" then
        ffi.cdef[[
            typedef struct { long x; long y; } POINT;
            bool GetCursorPos(POINT* point);
        ]]
        local point = ffi.new("POINT[1]")
        local success = ffi.C.GetCursorPos(point)
        if success then
            log(string.format("Posizione del mouse ottenuta: (%d, %d)", point[0].x, point[0].y))
            return point[0].x, point[0].y
        else
            local error_code = ffi.C.GetLastError()
            error_log(string.format("Impossibile ottenere la posizione del mouse. Codice errore: %d", error_code))
            return nil, nil
        end
    else
        error_log("Funzione get_mouse_pos non implementata per questo sistema operativo: " .. ffi.os)
        return nil, nil
    end
end

local function get_mouse_pos_multi_monitor()
    log("Inizio della funzione get_mouse_pos_multi_monitor()")
    local x, y = get_mouse_pos()
    if not x or not y then
        error_log("Impossibile ottenere la posizione del mouse in get_mouse_pos_multi_monitor")
        return 0, 0, 1920, 1080  -- Valori di fallback
    end
    log(string.format("Posizione del mouse ottenuta: (%d, %d)", x, y))
    
    local monitors = get_monitor_info()
    if not monitors or #monitors == 0 then
        error_log("Impossibile ottenere le informazioni sui monitor o nessun monitor rilevato")
        return x, y, 1920, 1080  -- Usa le coordinate assolute del mouse e dimensioni di default come fallback
    end
    log(string.format("Numero di monitor rilevati: %d", #monitors))
    
    -- Trova il monitor principale (di solito quello con left=0 e top=0)
    local primary_monitor = monitors[1]
    for _, monitor in ipairs(monitors) do
        if monitor.left == 0 and monitor.top == 0 then
            primary_monitor = monitor
            break
        end
    end
    
    -- Usa il monitor principale come riferimento
    local rel_x = x - primary_monitor.left
    local rel_y = y - primary_monitor.top
    local width = primary_monitor.right - primary_monitor.left
    local height = primary_monitor.bottom - primary_monitor.top
    
    log(string.format("Usando il monitor principale: (%d, %d), dimensioni: %dx%d", rel_x, rel_y, width, height))
    return rel_x, rel_y, width, height
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function is_valid_source_type(source)
    if not source then return false end
    local source_id = obs.obs_source_get_id(source)
    log("Controllando il tipo di sorgente: " .. source_id)
    local valid_types = {
        "ffmpeg_source",        -- Media source
        "browser_source",       -- Browser
        "vlc_source",           -- VLC Video Source
        "monitor_capture",      -- Display Capture
        "window_capture",       -- Window Capture
        "game_capture",         -- Game Capture
        "dshow_input",          -- Video Capture Device
        "av_capture_input"      -- Video Capture Device (macOS)
    }
    for _, valid_type in ipairs(valid_types) do
        if source_id == valid_type then
            log("Tipo di sorgente valido trovato: " .. source_id)
            return true
        end
    end
    log("Tipo di sorgente non valido: " .. source_id)
    return false
end

-- Modifica la funzione get_source_info_recursive
local function get_source_info_recursive(source_name, parent_scene, parent_info)
    local scene = parent_scene or safe_call(obs.obs_frontend_get_current_scene)
    if not scene then return nil end

    local scene_item = safe_call(obs.obs_scene_find_source, obs.obs_scene_from_source(scene), source_name)
    
    if not scene_item then
        local items = safe_call(obs.obs_scene_enum_items, obs.obs_scene_from_source(scene))
        if items then
            for _, item in ipairs(items) do
                local item_source = safe_call(obs.obs_sceneitem_get_source, item)
                if item_source and safe_call(obs.obs_source_get_type, item_source) == obs.OBS_SOURCE_TYPE_SCENE then
                    local pos = obs.vec2()
                    local scale = obs.vec2()
                    safe_call(function() obs.obs_sceneitem_get_pos(item, pos) end)
                    safe_call(function() obs.obs_sceneitem_get_scale(item, scale) end)
                    local nested_info = get_source_info_recursive(source_name, item_source, {
                        pos_x = (parent_info and parent_info.pos_x or 0) + pos.x,
                        pos_y = (parent_info and parent_info.pos_y or 0) + pos.y,
                        scale_x = (parent_info and parent_info.scale_x or 1) * scale.x,
                        scale_y = (parent_info and parent_info.scale_y or 1) * scale.y
                    })
                    if nested_info then
                        safe_call(obs.sceneitem_list_release, items)
                        safe_call(obs.obs_source_release, scene)
                        return nested_info
                    end
                end
            end
            safe_call(obs.sceneitem_list_release, items)
        end
        safe_call(obs.obs_source_release, scene)
        return nil
    end

    local source = safe_call(obs.obs_sceneitem_get_source, scene_item)
    if not source then 
        safe_call(obs.obs_source_release, scene)
        return nil 
    end

    local width = safe_call(obs.obs_source_get_width, source)
    local height = safe_call(obs.obs_source_get_height, source)
    
    local pos = obs.vec2()
    local scale = obs.vec2()
    safe_call(function() obs.obs_sceneitem_get_pos(scene_item, pos) end)
    safe_call(function() obs.obs_sceneitem_get_scale(scene_item, scale) end)
    
    local crop = obs.obs_sceneitem_crop()
    safe_call(obs.obs_sceneitem_get_crop, scene_item, crop)
    
    local transform = obs.obs_transform_info()
    safe_call(obs.obs_sceneitem_get_info, scene_item, transform)
    
    safe_call(obs.obs_source_release, scene)
    
    return {
        width = width,
        height = height,
        pos_x = (parent_info and parent_info.pos_x or 0) + pos.x,
        pos_y = (parent_info and parent_info.pos_y or 0) + pos.y,
        scale_x = (parent_info and parent_info.scale_x or 1) * scale.x,
        scale_y = (parent_info and parent_info.scale_y or 1) * scale.y,
        rot = transform.rot,
        crop_left = crop.left,
        crop_top = crop.top,
        crop_right = crop.right,
        crop_bottom = crop.bottom
    }
end

local function convert_screen_to_source_coords(mouse_x, mouse_y, source)
    local info = get_source_info_recursive(obs.obs_source_get_name(source))
    if not info then 
        error_log("Impossibile ottenere le informazioni della sorgente")
        return 0, 0 
    end
    
    local mouse_x, mouse_y, screen_width, screen_height = get_mouse_pos_multi_monitor()
    if not mouse_x or not mouse_y then
        error_log("Impossibile ottenere la posizione del mouse in convert_screen_to_source_coords")
        return 0, 0
    end
    
    local scale_x = base_width / screen_width
    local scale_y = base_height / screen_height
    
    mouse_x = mouse_x * scale_x
    mouse_y = mouse_y * scale_y
    
    local source_x = (mouse_x - info.pos_x) / info.scale_x
    local source_y = (mouse_y - info.pos_y) / info.scale_y
    
    source_x = source_x - info.crop_left
    source_y = source_y - info.crop_top
    
    if info.rot ~= 0 then
        local rad = math.rad(info.rot)
        local cos_rot = math.cos(rad)
        local sin_rot = math.sin(rad)
        local center_x = info.width / 2
        local center_y = info.height / 2
        local dx = source_x - center_x
        local dy = source_y - center_y
        source_x = center_x + (dx * cos_rot + dy * sin_rot)
        source_y = center_y + (-dx * sin_rot + dy * cos_rot)
    end
    
    log(string.format("Conversione coordinate - Mouse: (%.2f, %.2f), Sorgente: (%.2f, %.2f)", mouse_x, mouse_y, source_x, source_y))
    return source_x, source_y
end

local function is_mouse_inside_source(mouse_x, mouse_y, source)
    local info = get_source_info_recursive(obs.obs_source_get_name(source))
    if not info then return false end
    
    local mouse_x, mouse_y, screen_width, screen_height = get_mouse_pos_multi_monitor()
    
    local scale_x = base_width / screen_width
    local scale_y = base_height / screen_height
    
    mouse_x = mouse_x * scale_x
    mouse_y = mouse_y * scale_y
    
    local source_left = info.pos_x + info.crop_left * info.scale_x
    local source_top = info.pos_y + info.crop_top * info.scale_y
    local source_right, source_bottom
    
    if info.bounds_type == obs.OBS_BOUNDS_NONE then
        source_right = source_left + (info.width - info.crop_left - info.crop_right) * info.scale_x
        source_bottom = source_top + (info.height - info.crop_top - info.crop_bottom) * info.scale_y
    else
        source_right = source_left + info.bounds_x
        source_bottom = source_top + info.bounds_y
    end
    
    return mouse_x >= source_left and mouse_x <= source_right and mouse_y >= source_top and mouse_y <= source_bottom
end

local function choose_source()
    log("Inizio della funzione choose_source()")

    local function find_valid_source_in_scene(scene_source)
        local scene_name = obs.obs_source_get_name(scene_source)
        log("Controllando la scena: " .. scene_name)

        local scene = obs.obs_scene_from_source(scene_source)
        local items = obs.obs_scene_enum_items(scene)

        for _, item in ipairs(items) do
            local source = obs.obs_sceneitem_get_source(item)
            local source_name = obs.obs_source_get_name(source)
            local source_type = obs.obs_source_get_type(source)

            log("Controllando la sorgente: " .. source_name .. " (Tipo: " .. tostring(source_type) .. ")")

            if is_valid_source_type(source) then
                log("Sorgente valida trovata: " .. source_name)
                obs.sceneitem_list_release(items)
                return source_name, false
            elseif source_type == obs.OBS_SOURCE_TYPE_SCENE then
                local nested_info = get_source_info_recursive(source_name, source)
                if nested_info then
                    log("Sorgente valida trovata in scena annidata: " .. source_name)
                    obs.sceneitem_list_release(items)
                    return source_name, true
                end
            end
        end

        obs.sceneitem_list_release(items)
        return nil, false
    end

    local current_scene = obs.obs_frontend_get_current_scene()
    if not current_scene then
        log("Nessuna scena corrente trovata")
        return nil, false
    end

    local valid_source, is_nested = find_valid_source_in_scene(current_scene)
    obs.obs_source_release(current_scene)

    if valid_source then
        log("Sorgente valida trovata: " .. valid_source .. (is_nested and " (annidata)" or ""))
        return valid_source, is_nested
    end

    log("Nessuna sorgente valida trovata nella scena corrente")
    return nil, false
end

local function remove_filter_from_source(source)
    if source then
        local existing_filter = obs.obs_source_get_filter_by_name(source, CROP_FILTER_NAME)
        if existing_filter then
            obs.obs_source_filter_remove(source, existing_filter)
            obs.obs_source_release(existing_filter)
            log("Filtro rimosso dalla sorgente: " .. obs.obs_source_get_name(source))
        end
    end
end

local function update_crop(crop)
    if crop_filter then
        local settings = obs.obs_data_create()
        obs.obs_data_set_int(settings, "left", crop.left)
        obs.obs_data_set_int(settings, "top", crop.top)
        obs.obs_data_set_int(settings, "right", crop.right)
        obs.obs_data_set_int(settings, "bottom", crop.bottom)
        obs.obs_source_update(crop_filter, settings)
        obs.obs_data_release(settings)
    end
end

local function update_current_source()
    log("Inizio della funzione update_current_source()")
    local new_source_name, is_nested = choose_source()
    if new_source_name ~= source_name then
        if source then
            remove_filter_from_source(source)
        end
        
        source = obs.obs_get_source_by_name(new_source_name)
        if not source then
            error_log("Impossibile ottenere la sorgente: " .. new_source_name)
            panic_mode = true
            return
        end
        
        source_name = new_source_name
        
        if is_nested then
            local parent_scene = obs.obs_frontend_get_current_scene()
            crop_filter = safe_call(obs.obs_source_get_filter_by_name, parent_scene, CROP_FILTER_NAME)
            if not crop_filter then
                crop_filter = safe_call(obs.obs_source_create, "crop_filter", CROP_FILTER_NAME, nil, nil)
                if crop_filter then
                    safe_call(obs.obs_source_filter_add, parent_scene, crop_filter)
                    log("Nuovo filtro creato e applicato alla scena contenitore: " .. obs.obs_source_get_name(parent_scene))
                else
                    error_log("Impossibile creare il filtro per la scena contenitore")
                    panic_mode = true
                    return
                end
            end
            obs.obs_source_release(parent_scene)
        else
            crop_filter = safe_call(obs.obs_source_get_filter_by_name, source, CROP_FILTER_NAME)
            if not crop_filter then
                crop_filter = safe_call(obs.obs_source_create, "crop_filter", CROP_FILTER_NAME, nil, nil)
                if crop_filter then
                    safe_call(obs.obs_source_filter_add, source, crop_filter)
                    log("Nuovo filtro creato e applicato alla sorgente: " .. source_name)
                else
                    error_log("Impossibile creare il filtro per la sorgente: " .. source_name)
                    panic_mode = true
                    return
                end
            end
        end
        
        original_crop = {left = 0, top = 0, right = 0, bottom = 0}
        current_crop = {left = 0, top = 0, right = 0, bottom = 0}
        safe_call(update_crop, original_crop)
        
        log("Nuova sorgente selezionata: " .. source_name .. (is_nested and " (annidata)" or ""))
    else
        log("Nessun aggiornamento necessario per la sorgente")
    end
end

local function get_target_crop(mouse_x, mouse_y, source, screen_width, screen_height)
    log(string.format("Inizio get_target_crop: mouse_x=%d, mouse_y=%d, screen_width=%d, screen_height=%d", 
        mouse_x, mouse_y, screen_width, screen_height))
    
    local source_width = obs.obs_source_get_width(source)
    local source_height = obs.obs_source_get_height(source)
    log(string.format("Dimensioni sorgente: %dx%d", source_width, source_height))
    
    local scale_x = source_width / screen_width
    local scale_y = source_height / screen_height
    log(string.format("Fattori di scala: scale_x=%.2f, scale_y=%.2f", scale_x, scale_y))
    
    local target_x = math.floor(mouse_x * scale_x - (source_width / zoom_value / 2))
    local target_y = math.floor(mouse_y * scale_y - (source_height / zoom_value / 2))
    local target_width = math.floor(source_width / zoom_value)
    local target_height = math.floor(source_height / zoom_value)
    
    target_x = math.max(0, math.min(target_x, source_width - target_width))
    target_y = math.max(0, math.min(target_y, source_height - target_height))
    
    log(string.format("Target crop calcolato: x=%d, y=%d, width=%d, height=%d", 
        target_x, target_y, target_width, target_height))
    
    return {
        left = target_x,
        top = target_y,
        right = source_width - (target_x + target_width),
        bottom = source_height - (target_y + target_height)
    }
end

-- Modifica la funzione update_zoom
local function update_zoom()
    log("Inizio della funzione update_zoom()")
    if not zoom_active then 
        log("Zoom non attivo")
        return 
    end
    
    safe_call(update_current_source)
    if not source or not crop_filter then 
        error_log("Sorgente o filtro non disponibili")
        return 
    end

    log("Aggiornamento zoom - Sorgente: " .. obs.obs_source_get_name(source))

    local mouse_x, mouse_y, screen_width, screen_height = safe_call(get_mouse_pos_multi_monitor)
    if not mouse_x or not mouse_y or not screen_width or not screen_height then
        error_log("Impossibile ottenere la posizione del mouse o le dimensioni dello schermo")
        return
    end

    log(string.format("Posizione del mouse: (%d, %d), Dimensioni schermo: %dx%d", mouse_x, mouse_y, screen_width, screen_height))

    local source_x, source_y = safe_call(convert_screen_to_source_coords, mouse_x, mouse_y, source)
    if not source_x or not source_y then
        error_log("Errore nella conversione delle coordinate")
        return
    end
    
    log(string.format("Coordinate sorgente: (%d, %d)", source_x, source_y))
    
    local zoom_target = safe_call(get_target_crop, mouse_x, mouse_y, source, screen_width, screen_height)
    if not zoom_target then
        error_log("Impossibile calcolare il target dello zoom")
        return
    end
    
    log(string.format("Zoom target calcolato: left=%d, top=%d, right=%d, bottom=%d", 
        zoom_target.left, zoom_target.top, zoom_target.right, zoom_target.bottom))
    
    current_crop = {
        left = lerp(current_crop.left, zoom_target.left, zoom_speed),
        top = lerp(current_crop.top, zoom_target.top, zoom_speed),
        right = lerp(current_crop.right, zoom_target.right, zoom_speed),
        bottom = lerp(current_crop.bottom, zoom_target.bottom, zoom_speed)
    }
    
    safe_call(update_crop, current_crop)
    
    log(string.format("Zoom applicato - Crop: left=%.2f, top=%.2f, right=%.2f, bottom=%.2f", 
                      current_crop.left, current_crop.top, current_crop.right, current_crop.bottom))
end

local function on_zoom_hotkey(pressed)
    if pressed then
        log("Hotkey zoom premuto")
        if panic_mode then
            error_log("Lo script è in modalità panic. Resetta lo script per continuare.")
            return
        end
        zoom_active = not zoom_active
        log("Zoom attivato: " .. tostring(zoom_active))
        if zoom_active then
            safe_call(update_current_source)
            if not source then
                error_log("Sorgente non disponibile. Assicurati di avere una sorgente valida nella scena corrente.")
                zoom_active = false
                return
            end
            log("Chiamata a get_mouse_pos_multi_monitor()")
            local mouse_x, mouse_y, screen_width, screen_height = get_mouse_pos_multi_monitor()
            log(string.format("Risultato di get_mouse_pos_multi_monitor: x=%s, y=%s, width=%s, height=%s", 
                tostring(mouse_x), tostring(mouse_y), tostring(screen_width), tostring(screen_height)))
            
            zoom_target = safe_call(get_target_crop, mouse_x, mouse_y, source, screen_width, screen_height)
            if not zoom_target then
                error_log("Impossibile calcolare il target dello zoom")
                zoom_active = false
                return
            end
            log(string.format("Zoom target calcolato: left=%d, top=%d, right=%d, bottom=%d", 
                zoom_target.left, zoom_target.top, zoom_target.right, zoom_target.bottom))
            if not update_timer then
                update_timer = obs.timer_add(update_zoom, 33)  -- Aggiorna circa 30 volte al secondo
            end
        else
            follow_active = false
            safe_call(update_crop, original_crop)
            zoom_target = nil
            if update_timer then
                obs.timer_remove(update_timer)
                update_timer = nil
            end
        end
    end
end

local function on_follow_hotkey(pressed)
    if pressed then
        if panic_mode then
            error_log("Lo script è in modalità panic. Resetta lo script per continuare.")
            return
        end
        if zoom_active then
            follow_active = not follow_active
            log("Segui mouse attivato: " .. tostring(follow_active))
            if follow_active then
                local mouse_x, mouse_y = get_mouse_pos()
                zoom_target = get_target_crop(mouse_x, mouse_y, source)
            else
                zoom_center = nil
            end
        else
            log("Il follow può essere attivato solo quando lo zoom è attivo")
        end
    end
end

-- Funzioni OBS
function script_description()
    return "Zoom e segui il mouse per OBS Studio. Versione " .. VERSION
end

function script_properties()
    local props = obs.obs_properties_create()
    
    obs.obs_properties_add_button(props, "reset_button", "Resetta Script", function()
        reset_script_state()
        log("Script resettato")
        return true
    end)
    
    local sources = obs.obs_properties_add_list(props, "default_source", "Sorgente di default", obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING)
    local sources_list = obs.obs_enum_sources()
    if sources_list then
        obs.obs_property_list_add_string(sources, "Nessuna", "")
        for _, source in ipairs(sources_list) do
            if is_valid_source_type(source) then
                local name = obs.obs_source_get_name(source)
                obs.obs_property_list_add_string(sources, name, name)
            end
        end
    end
    obs.source_list_release(sources_list)
    
    obs.obs_properties_add_float_slider(props, "zoom_value", "Valore Zoom", 1.1, 5.0, 0.1)
    obs.obs_properties_add_float_slider(props, "zoom_speed", "Velocità Zoom", 0.01, 1.0, 0.01)
    obs.obs_properties_add_float_slider(props, "follow_speed", "Velocità Segui", 0.01, 1.0, 0.01)
    obs.obs_properties_add_bool(props, "debug_logging", "Abilita log di debug")

    obs.obs_properties_add_bool(props, "use_custom_base_resolution", "Usa risoluzione di base personalizzata")
    obs.obs_properties_add_int(props, "custom_base_width", "Larghezza di base personalizzata", 1, 7680, 1)
    obs.obs_properties_add_int(props, "custom_base_height", "Altezza di base personalizzata", 1, 4320, 1)

    return props
end

function script_defaults(settings)
    obs.obs_data_set_default_double(settings, "zoom_value", 2.0)
    obs.obs_data_set_default_double(settings, "zoom_speed", 0.1)
    obs.obs_data_set_default_double(settings, "follow_speed", 0.1)
    obs.obs_data_set_default_bool(settings, "debug_logging", false)
    obs.obs_data_set_default_bool(settings, "use_custom_base_resolution", false)
    obs.obs_data_set_default_int(settings, "custom_base_width", 1920)
    obs.obs_data_set_default_int(settings, "custom_base_height", 1080)
end

function script_update(settings)
    default_source_name = obs.obs_data_get_string(settings, "default_source")
    zoom_value = obs.obs_data_get_double(settings, "zoom_value")
    zoom_speed = obs.obs_data_get_double(settings, "zoom_speed")
    follow_speed = obs.obs_data_get_double(settings, "follow_speed")
    debug_logging = obs.obs_data_get_bool(settings, "debug_logging")

    use_custom_base_resolution = obs.obs_data_get_bool(settings, "use_custom_base_resolution")
    if use_custom_base_resolution then
        base_width = obs.obs_data_get_int(settings, "custom_base_width")
        base_height = obs.obs_data_get_int(settings, "custom_base_height")
    else
        -- Usa valori predefiniti se non viene specificata una risoluzione personalizzata
        base_width = 1920
        base_height = 1080
    end

    log(string.format("Risoluzione di base: %dx%d", base_width, base_height))

    update_current_source()
end

function script_load(settings)
    script_update(settings)

    hotkey_zoom_id = obs.obs_hotkey_register_frontend(ZOOM_NAME_TOG, ZOOM_DESC_TOG, on_zoom_hotkey)
    local hotkey_save_array = obs.obs_data_get_array(settings, ZOOM_NAME_TOG)
    obs.obs_hotkey_load(hotkey_zoom_id, hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)

    hotkey_follow_id = obs.obs_hotkey_register_frontend(FOLLOW_NAME_TOG, FOLLOW_DESC_TOG, on_follow_hotkey)
    hotkey_save_array = obs.obs_data_get_array(settings, FOLLOW_NAME_TOG)
    obs.obs_hotkey_load(hotkey_follow_id, hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)

    log("Script caricato")
end

function script_save(settings)
    local hotkey_save_array = obs.obs_hotkey_save(hotkey_zoom_id)
    obs.obs_data_set_array(settings, ZOOM_NAME_TOG, hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)

    hotkey_save_array = obs.obs_hotkey_save(hotkey_follow_id)
    obs.obs_data_set_array(settings, FOLLOW_NAME_TOG, hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)
end

function script_unload()
    remove_filter_from_source(source)
    safe_release(source)
    safe_release(crop_filter)
    if update_timer then
        obs.timer_remove(update_timer)
        update_timer = nil
    end
    log("Script scaricato")
end