local wezterm = require 'wezterm'
local config = wezterm.config_builder()

--- ---------------------------------------------------------------------------
--- Variables
--- ---------------------------------------------------------------------------
-- Wallpapers: synced from repo ./wallpaper → ~/.config/wezterm/wallpaper
local WALLPAPER_DIR = wezterm.home_dir .. '/.config/wezterm/wallpaper'
local DEFAULT_TRANSPARENCY_STEP = 0.05
-- Image layer opacity (also live via Ctrl+[ / Ctrl+])
local DEFAULT_BACKGROUND_OPACITY = 0.95
-- Color tint over the image — lower = more wallpaper shows through
-- Live via Ctrl+{ / Ctrl+} (Ctrl+Shift+[ / ])
local DEFAULT_OVERLAY_OPACITY = 0

--- ---------------------------------------------------------------------------
--- Global State
--- ---------------------------------------------------------------------------
local global = wezterm.GLOBAL
global.wallpapers = global.wallpapers or {}
global.current_wallpaper_type = global.current_wallpaper_type or nil
global.selected_wallpaper = global.selected_wallpaper or 1
global.pre_toggle_opacity = global.pre_toggle_opacity or DEFAULT_BACKGROUND_OPACITY
global.overlay_opacity = global.overlay_opacity or DEFAULT_OVERLAY_OPACITY
global.unseen_notified = global.unseen_notified or {}

--- ---------------------------------------------------------------------------
--- Theme (dark only)
--- ---------------------------------------------------------------------------
local THEME = {
  name = 'Catppuccin Macchiato',
  highlight = '#ffcc66',
  dim = wezterm.color.get_builtin_schemes()['Catppuccin Macchiato']['selection_bg'],
  overlay = '#0f172a', -- tint color drawn over wallpapers
}

--- ---------------------------------------------------------------------------
--- Helpers
--- ---------------------------------------------------------------------------
local function basename(s)
  return string.gsub(s, '(.*[/\\])(.*)', '%2')
end

local function set_alpha(c, a)
  local fh, fs, fl, _ = wezterm.color.parse(c):hsla()
  return wezterm.color.from_hsla(fh, fs, fl, a)
end

local function prompt_line()
  return wezterm.action.PromptInputLine {
    description = 'Enter new name for tab',
    action = wezterm.action_callback(function(window, pane, line)
      if line then
        window:active_tab():set_title(line)
      end
    end)
  }
end

--- ---------------------------------------------------------------------------
--- tmux (WezTerm tab = epic session; tmux windows = stories)
--- ---------------------------------------------------------------------------
local function file_exists(path)
  local f = io.open(path, 'r')
  if f then
    f:close()
    return true
  end
  return false
end

local function resolve_tmux()
  -- Do NOT probe missing paths with run_child_process — it errors hard
  -- (ENOENT) and aborts the whole keybinding instead of trying the next path.
  local user = os.getenv('USER') or 'brianallen'
  local candidates = {
    wezterm.home_dir .. '/.nix-profile/bin/tmux',
    '/etc/profiles/per-user/' .. user .. '/bin/tmux',
    '/run/current-system/sw/bin/tmux',
    '/opt/homebrew/bin/tmux',
    '/usr/local/bin/tmux',
  }
  for _, path in ipairs(candidates) do
    if file_exists(path) then
      return path
    end
  end
  return 'tmux'
end

local function sanitize_session_name(name)
  local s = name:gsub('^%s+', ''):gsub('%s+$', '')
  s = s:gsub('%s+', '-')
  s = s:gsub('[^%w%-%_]', '')
  return s
end

local function list_tmux_sessions()
  local tmux = resolve_tmux()
  local call_ok, success, stdout = pcall(wezterm.run_child_process, {
    tmux, 'list-sessions', '-F', '#{session_name}',
  })
  local sessions = {}
  if call_ok and success and stdout and #stdout > 0 then
    for name in stdout:gmatch('[^\r\n]+') do
      if #name > 0 then
        table.insert(sessions, name)
      end
    end
  end
  table.sort(sessions)
  return sessions
end

local function spawn_tmux_tab(window, session_name)
  local name = sanitize_session_name(session_name)
  if not name or #name == 0 then
    window:toast_notification('tmux', 'Invalid session name', nil, 3000)
    return
  end

  local tmux = resolve_tmux()
  if tmux ~= 'tmux' and not file_exists(tmux) then
    window:toast_notification('tmux', 'tmux binary not found', nil, 4000)
    return
  end

  local ok, tab_or_err = pcall(function()
    local tab, _pane = window:mux_window():spawn_tab {
      args = { tmux, 'new-session', '-A', '-s', name },
    }
    return tab
  end)

  if not ok then
    window:toast_notification('tmux', 'Spawn failed: ' .. tostring(tab_or_err), nil, 5000)
    wezterm.log_error('tmux spawn failed: ' .. tostring(tab_or_err))
    return
  end

  local tab = tab_or_err
  if tab then
    tab:set_title(name)
  end
end

local function prompt_new_tmux_session()
  return wezterm.action.PromptInputLine {
    description = 'New tmux session name (epic)',
    action = wezterm.action_callback(function(window, pane, line)
      if line and #line > 0 then
        spawn_tmux_tab(window, line)
      end
    end),
  }
end

local function tmux_session_picker()
  return wezterm.action_callback(function(window, pane)
    local choices = {
      { id = '__new__', label = '+ New session...' },
    }
    for _, name in ipairs(list_tmux_sessions()) do
      table.insert(choices, { id = name, label = name })
    end

    window:perform_action(wezterm.action.InputSelector {
      title = 'tmux session (epic)',
      fuzzy_description = 'Attach or create session: ',
      choices = choices,
      fuzzy = true,
      action = wezterm.action_callback(function(window, pane, id, _label)
        if not id then
          return
        end
        if id == '__new__' then
          window:perform_action(prompt_new_tmux_session(), pane)
        else
          spawn_tmux_tab(window, id)
        end
      end),
    }, pane)
  end)
end

local function get_wallpapers()
  local wallpaper_types = {}
  local ok, entries = pcall(wezterm.read_dir, WALLPAPER_DIR)
  if not ok or not entries then
    return {}
  end

  for _, path in ipairs(entries) do
    local name = basename(path)
    if not name:match("^%.") then
      table.insert(wallpaper_types, name)
    end
  end

  local wallpapers = {}
  for _, wallpaper_type in ipairs(wallpaper_types) do
    -- skip loose files in wallpaper/ (README.md, .gitkeep, etc.)
    if not wallpaper_type:match("%.") then
      local images = {}
      local type_dir = WALLPAPER_DIR .. '/' .. wallpaper_type
      local type_ok, type_entries = pcall(wezterm.read_dir, type_dir)
      if type_ok and type_entries then
        for _, path in ipairs(type_entries) do
          local filename = basename(path)
          if not filename:match("^%.") then
            table.insert(images, filename)
          end
        end
      end
      if #images > 0 then
        wallpapers[wallpaper_type] = images
      end
    end
  end

  return wallpapers
end

local function ensure_wallpapers_loaded()
  local has_wallpapers = false
  for _ in pairs(global.wallpapers) do
    has_wallpapers = true
    break
  end

  if not has_wallpapers then
    global.wallpapers = get_wallpapers()
    local wallpaper_types = {}
    for type_name, _ in pairs(global.wallpapers) do
      table.insert(wallpaper_types, type_name)
    end
    table.sort(wallpaper_types)
    if #wallpaper_types > 0 then
      global.current_wallpaper_type = wallpaper_types[1]
    end
  end
end

local function background_with_overlay(image_path, background_image_opacity)
  return {
    {
      source = { File = image_path },
      opacity = background_image_opacity
    },
    {
      source = { Color = THEME.overlay },
      width = "100%",
      height = "100%",
      opacity = global.overlay_opacity
    }
  }
end

local function ensure_overlay_layer(background)
  if #background >= 2 then
    return background
  end
  -- Solid / single-layer bg: keep it as layer 1, add tint on top
  table.insert(background, {
    source = { Color = THEME.overlay },
    width = "100%",
    height = "100%",
    opacity = global.overlay_opacity,
  })
  return background
end

local function cycle_wallpaper_type()
  local types = {}
  for name in pairs(global.wallpapers) do
    table.insert(types, name)
  end
  table.sort(types)

  if #types == 0 then return false end

  local current_idx = 1
  for i, name in ipairs(types) do
    if name == global.current_wallpaper_type then
      current_idx = i
      break
    end
  end

  global.current_wallpaper_type = types[(current_idx % #types) + 1]
  global.selected_wallpaper = 1
  return true
end

local function cycle_wallpaper(window)
  if not global.current_wallpaper_type then return false end

  local images = global.wallpapers[global.current_wallpaper_type]
  if not images or #images == 0 then return false end

  local overrides = window:get_config_overrides() or {}
  local current_opacity = overrides.background and overrides.background[1] and overrides.background[1].opacity or
      DEFAULT_BACKGROUND_OPACITY
  local image_path = WALLPAPER_DIR .. '/' .. global.current_wallpaper_type .. '/' .. images[global.selected_wallpaper]

  overrides.background = background_with_overlay(image_path, current_opacity)
  window:set_config_overrides(overrides)

  global.selected_wallpaper = (global.selected_wallpaper % #images) + 1
  return true
end

local function create_tab_bar_colors(theme)
  return {
    background = "none",
    new_tab = { bg_color = "none", fg_color = theme.dim },
    new_tab_hover = { bg_color = "none", fg_color = theme.highlight },
    inactive_tab = { bg_color = "none", fg_color = theme.dim },
    inactive_tab_hover = {
      bg_color = "none",
      fg_color = wezterm.color.parse(wezterm.color.get_builtin_schemes()[theme.name]['selection_bg']):lighten(0.3)
    },
    active_tab = { bg_color = "none", fg_color = theme.highlight, intensity = 'Bold' },
    inactive_tab_edge = "none",
  }
end

--- ---------------------------------------------------------------------------
--- Configuration
--- ---------------------------------------------------------------------------
config.status_update_interval = 1000
config.leader = { key = 'a', mods = 'CTRL', timeout_milliseconds = 1000 }

config.font_size = 14
config.command_palette_font_size = 14

config.webgpu_power_preference = "HighPerformance"
config.front_end = "WebGpu"
config.macos_window_background_blur = 10
config.max_fps = 120
config.animation_fps = 120

-- show_close_tab_button_in_tabs is too new for Homebrew cask (20240203); omit it
config.hide_tab_bar_if_only_one_tab = false
config.tab_bar_at_bottom = false
config.use_fancy_tab_bar = true
config.window_decorations = "RESIZE|MACOS_FORCE_DISABLE_SHADOW"
config.window_padding = {
  left = 10,
  right = 10,
  top = 8,
  bottom = 8,
}
config.window_frame = {
  active_titlebar_bg = "none",
  inactive_titlebar_bg = "none",
  font_size = 14,
}

config.default_cursor_style = "BlinkingBar"
config.cursor_blink_rate = 700
config.scrollback_lines = 10000
-- Desktop toast on BEL; skip system beep (agents / printf '\\a')
config.audible_bell = 'Disabled'

-- Ensure Nix / Homebrew tmux is visible when launched from Dock / Spotlight
do
  local home = wezterm.home_dir
  local path = os.getenv('PATH') or ''
  local extras = {
    home .. '/.nix-profile/bin',
    '/etc/profiles/per-user/' .. (os.getenv('USER') or 'brianallen') .. '/bin',
    '/run/current-system/sw/bin',
    '/opt/homebrew/bin',
  }
  for _, dir in ipairs(extras) do
    if not path:find(dir, 1, true) then
      path = dir .. ':' .. path
    end
  end
  config.set_environment_variables = {
    PATH = path,
  }
end

config.inactive_pane_hsb = { saturation = 1, brightness = 1 }
config.color_scheme = THEME.name
config.colors = {
  cursor_bg = THEME.highlight,
  cursor_border = THEME.highlight,
  split = tostring(set_alpha(wezterm.color.get_builtin_schemes()[THEME.name]['selection_bg'], 0.9)),
  tab_bar = create_tab_bar_colors(THEME),
}

local custom_bg = wezterm.color.parse(wezterm.color.get_builtin_schemes()[THEME.name]['background'])
    :lighten(0.1)

config.background = { {
  source = { Color = tostring(custom_bg) },
  width = "100%",
  height = "100%",
  opacity = DEFAULT_BACKGROUND_OPACITY
} }

-- Prefer Leader+t / Cmd+Shift+t / command palette "tmux-session-picker"
-- (dynamic session list; launch_menu can't query tmux at config load time)

--- ---------------------------------------------------------------------------
--- Keys
--- ---------------------------------------------------------------------------
-- WezTerm leader: Ctrl+a | tmux prefix: Ctrl+b (do NOT bind Ctrl+b in WezTerm)
-- Inside an epic tab, use tmux for splits/windows — not WezTerm Leader+|/=
config.keys = {
  -- panes / tabs (WezTerm)
  { key = 'w', mods = 'SUPER',       action = wezterm.action.CloseCurrentPane { confirm = false } },
  { key = 'p', mods = 'SUPER',       action = wezterm.action.ActivateCommandPalette },
  { key = 'e', mods = 'SUPER',       action = prompt_line() },

  -- tmux epics: new WezTerm tab → tmux new-session -A -s <name>
  { key = 't', mods = 'LEADER',      action = wezterm.action.EmitEvent 'tmux-session-picker' },
  { key = 't', mods = 'SUPER|SHIFT', action = wezterm.action.EmitEvent 'tmux-session-picker' },
  { key = 'n', mods = 'LEADER',      action = wezterm.action.EmitEvent 'tmux-new-session' },

  -- wallpaper / opacity (Ctrl+Alt — leaves Ctrl+b free for tmux)
  { key = 'n', mods = 'CTRL|ALT',    action = wezterm.action.EmitEvent 'cycle-wallpaper-folder' },
  { key = 'b', mods = 'CTRL|ALT',    action = wezterm.action.EmitEvent 'cycle-wallpaper' },
  { key = 'B', mods = 'CTRL|ALT|SHIFT', action = wezterm.action.EmitEvent 'clear-background' },
  { key = '[', mods = 'CTRL',        action = wezterm.action.EmitEvent 'opacity-dec' },
  { key = ']', mods = 'CTRL',        action = wezterm.action.EmitEvent 'opacity-inc' },
  { key = '[', mods = 'CTRL|SHIFT',  action = wezterm.action.EmitEvent 'overlay-dec' },
  { key = ']', mods = 'CTRL|SHIFT',  action = wezterm.action.EmitEvent 'overlay-inc' },
  { key = 'o', mods = 'CTRL',        action = wezterm.action.EmitEvent 'toggle-transparency' },
}

--- ---------------------------------------------------------------------------
--- Events
--- ---------------------------------------------------------------------------
wezterm.on('format-tab-title', function(tab)
  local title = tab.tab_title
  if title and #title > 0 then
    -- keep custom title (tmux epic name)
  elseif tab.tab_index == 0 then
    title = 'main'
  else
    title = tostring(tab.tab_index + 1)
  end

  local has_unseen = false
  for _, pane in ipairs(tab.panes) do
    if pane.has_unseen_output then
      has_unseen = true
      break
    end
  end

  if tab.is_active then
    return {
      { Foreground = { Color = THEME.highlight } },
      { Text = ' ' .. title .. ' ' },
    }
  end

  if has_unseen then
    return {
      { Foreground = { Color = THEME.highlight } },
      { Text = ' • ' .. title .. ' ' },
    }
  end

  return {
    { Foreground = { Color = THEME.dim } },
    { Text = ' ' .. title .. ' ' },
  }
end)

wezterm.on('tmux-session-picker', function(window, pane)
  window:perform_action(tmux_session_picker(), pane)
end)

wezterm.on('tmux-new-session', function(window, pane)
  window:perform_action(prompt_new_tmux_session(), pane)
end)

wezterm.on('bell', function(window, pane)
  local title = pane:get_title() or 'terminal'
  window:toast_notification('WezTerm', 'Activity: ' .. title, nil, 4000)
end)

wezterm.on('cycle-wallpaper', function(window, _)
  ensure_wallpapers_loaded()
  cycle_wallpaper(window)
end)

wezterm.on('cycle-wallpaper-folder', function(window, _)
  ensure_wallpapers_loaded()
  if cycle_wallpaper_type() then
    cycle_wallpaper(window)
  end
end)

wezterm.on('clear-background', function(window, _)
  local overrides = window:get_config_overrides() or {}
  overrides.background = nil
  window:set_config_overrides(overrides)
end)

wezterm.on('toggle-transparency', function(window, _)
  local overrides = window:get_config_overrides() or {}
  overrides.background = overrides.background or config.background

  local current = overrides.background[1].opacity or 1.0
  local is_transparent = current < 1.0

  if is_transparent then global.pre_toggle_opacity = current end
  overrides.background[1].opacity = is_transparent and 1.0 or global.pre_toggle_opacity
  window:set_config_overrides(overrides)
end)

wezterm.on('opacity-inc', function(window, _)
  local overrides = window:get_config_overrides() or {}
  overrides.background = overrides.background or config.background

  local current = overrides.background[1].opacity or 1.0
  overrides.background[1].opacity = math.min(current + DEFAULT_TRANSPARENCY_STEP, 1.0)
  window:set_config_overrides(overrides)
end)

wezterm.on('opacity-dec', function(window, _)
  local overrides = window:get_config_overrides() or {}
  overrides.background = overrides.background or config.background

  local current = overrides.background[1].opacity or 1.0
  overrides.background[1].opacity = math.max(current - DEFAULT_TRANSPARENCY_STEP, 0.2)
  window:set_config_overrides(overrides)
end)

wezterm.on('overlay-inc', function(window, _)
  local overrides = window:get_config_overrides() or {}
  overrides.background = ensure_overlay_layer(overrides.background or config.background)

  local current = overrides.background[2].opacity or global.overlay_opacity
  global.overlay_opacity = math.min(current + DEFAULT_TRANSPARENCY_STEP, 1.0)
  overrides.background[2].opacity = global.overlay_opacity
  window:set_config_overrides(overrides)
end)

wezterm.on('overlay-dec', function(window, _)
  local overrides = window:get_config_overrides() or {}
  overrides.background = ensure_overlay_layer(overrides.background or config.background)

  local current = overrides.background[2].opacity or global.overlay_opacity
  global.overlay_opacity = math.max(current - DEFAULT_TRANSPARENCY_STEP, 0.0)
  overrides.background[2].opacity = global.overlay_opacity
  window:set_config_overrides(overrides)
end)

wezterm.on('update-status', function(window, _)
  -- Toast once when a background tab gets new output (e.g. Claude finished)
  local mux_win = window:mux_window()
  for _, ti in ipairs(mux_win:tabs_with_info()) do
    local tab = ti.tab
    local id = tostring(tab:tab_id())
    local has_unseen = false
    for _, pi in ipairs(tab:panes_with_info()) do
      if pi.has_unseen_output then
        has_unseen = true
        break
      end
    end

    if has_unseen and not ti.is_active then
      if not global.unseen_notified[id] then
        global.unseen_notified[id] = true
        local title = tab:get_title()
        if not title or #title == 0 then
          title = 'tab'
        end
        window:toast_notification('WezTerm', 'Output in: ' .. title, nil, 5000)
      end
    else
      global.unseen_notified[id] = nil
    end
  end

  if window:leader_is_active() then
    window:set_right_status(wezterm.format {
      { Foreground = { Color = THEME.highlight } },
      { Text = ' LEADER ' },
    })
  else
    window:set_right_status('')
  end
end)

wezterm.on('gui-startup', function()
  ensure_wallpapers_loaded()
end)

return config
