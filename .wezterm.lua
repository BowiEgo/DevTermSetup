local wezterm = require 'wezterm'
local act = wezterm.action

local config = wezterm.config_builder()

-- 平台检测（wezterm.target_triple 例如: x86_64-pc-windows-msvc / aarch64-apple-darwin / x86_64-unknown-linux-gnu）
local triple = wezterm.target_triple
local is_windows = triple:find('windows', 1, true) ~= nil
local is_macos = triple:find('darwin', 1, true) ~= nil

-- ============ 默认 shell 回退链 ============
-- Windows: pwsh → powershell → cmd
-- macOS/Linux: $SHELL → zsh → bash → fish → pwsh → sh
local function file_exists(p)
  if not p then return false end
  local f = io.open(p, 'r')
  if f then
    f:close()
    return true
  end
  return false
end

local function find_in_path(name)
  local sep = is_windows and ';' or ':'
  local path = os.getenv('PATH') or ''
  for dir in path:gmatch('[^' .. sep .. ']+') do
    dir = dir:gsub('[\\/]$', '')
    local p = dir .. (is_windows and '\\' or '/') .. name
    if file_exists(p) then return p end
  end
  return nil
end

local function resolve_default_prog()
  if is_windows then
    local windir = os.getenv('WINDIR') or 'C:\\Windows'
    local candidates = {
      find_in_path('pwsh.exe'),
      'C:\\Program Files\\PowerShell\\7\\pwsh.exe',
      find_in_path('powershell.exe'),
      windir .. '\\System32\\WindowsPowerShell\\v1.0\\powershell.exe',
      os.getenv('COMSPEC'),
    }
    for _, p in ipairs(candidates) do
      if file_exists(p) then return { p } end
    end
    return { 'cmd.exe' }
  end
  -- macOS / Linux：优先尊重用户的登录 shell（$SHELL）
  local shell = os.getenv('SHELL')
  if file_exists(shell) then return { shell } end
  for _, s in ipairs({ 'zsh', 'bash', 'fish', 'pwsh', 'sh' }) do
    local p = find_in_path(s)
    if p then return { p } end
  end
  return { '/bin/sh' }
end

config.default_prog = resolve_default_prog()

config.font = wezterm.font_with_fallback {
  'JetBrains Mono',
  'Menlo',
  'DejaVu Sans Mono',
  'Noto Sans Mono',
}
config.font_size = 14
config.line_height = 1.08
config.initial_cols = 240
config.initial_rows = 60

config.disable_default_key_bindings = true

config.colors = {
  foreground = '#dce7f7',
  background = '#07111f',
  cursor_bg = '#8bdcff',
  cursor_fg = '#07111f',
  selection_bg = '#24466f',
  selection_fg = '#ffffff',
}

config.window_decorations = 'RESIZE'
config.window_background_opacity = 0.94
if is_macos then
  config.macos_window_background_blur = 24
end
config.window_padding = {
  left = 14,
  right = 14,
  top = 12,
  bottom = 12,
}

config.use_fancy_tab_bar = false
config.hide_tab_bar_if_only_one_tab = true
config.tab_bar_at_bottom = true
config.scrollback_lines = 10000
config.audible_bell = 'Disabled'

config.leader = { key = 'a', mods = 'CTRL', timeout_milliseconds = 1000 }
config.keys = {
  {
    key = '|',
    mods = 'LEADER|SHIFT',
    action = act.SplitHorizontal { domain = 'CurrentPaneDomain' },
  },
  {
    key = '-',
    mods = 'LEADER',
    action = act.SplitVertical { domain = 'CurrentPaneDomain' },
  },
  { key = 'h', mods = 'LEADER', action = act.ActivatePaneDirection 'Left' },
  { key = 'j', mods = 'LEADER', action = act.ActivatePaneDirection 'Down' },
  { key = 'k', mods = 'LEADER', action = act.ActivatePaneDirection 'Up' },
  { key = 'l', mods = 'LEADER', action = act.ActivatePaneDirection 'Right' },
  { key = 'z', mods = 'LEADER', action = act.TogglePaneZoomState },
  { key = 'c', mods = 'LEADER', action = act.SpawnTab 'CurrentPaneDomain' },
  {
    key = 'a',
    mods = 'LEADER|CTRL',
    action = act.SendKey { key = 'a', mods = 'CTRL' },
  },
}

return config