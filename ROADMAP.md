# Basket Roadmap

> Doom Emacs philosophy for a window manager: opinionated defaults, friendly to newcomers, unrestricted for ricers.

## Architecture Overview

Basket is a doom-style window manager client for River compositor, built on kwm.

**Config hierarchy:**
- `defaults.zig` - Sane defaults (compile-time)
- `theme.zon` - Visual settings (borders, gaps, scale)
- `config.zon` - Popup settings (font, theme preset, position)
- `basket.zon` - Keybinding overrides (unbind/rebind)
- `delta.zon` + `+module.zon` - Chord tree menus

**Core components:**
- `kwm/` - Window management core (seats, bindings, layouts)
- `popup.zig` + `surface/layer.zig` - Delta popup menu
- `ipc/` - Unix socket control (`$XDG_RUNTIME_DIR/basket.sock`)
- `output_config.zig` - HiDPI scaling via wlr-output-management

---

## Completed

### Display & Rendering
- [x] HiDPI scaling via wlr-output-management protocol
- [x] Theme loading from theme.zon (borders, gaps, colors)
- [x] Font configuration from config.zon (family, size)
- [x] Position configuration from config.zon (7 anchor positions)
- [x] fcft font rendering in popup menu

### Configuration
- [x] Doom-style config hierarchy
- [x] Runtime keybinding loading (defaults + basket.zon merge)
- [x] Unbind support in basket.zon
- [x] Delta chord tree loading from delta.zon
- [x] Module injection via +name.zon files
- [x] Theme presets (gruvbox, catppuccin, nord, dracula, tokyo_night)

### IPC (basketholder)
- [x] Unix socket server
- [x] Window management commands (close, focus, swap, zoom)
- [x] Layout switching (tile, monocle, scroller, float)
- [x] Tag management (tag, window-tag, toggle variants)
- [x] Mode switching (lock, default, floating, passthrough)
- [x] Popup control (popup, hide-popup)
- [x] Session control (quit, restart)
- [x] Spawn commands (spawn, spawn-shell)

### Input
- [x] Modal keybinding system (bindings per mode)
- [x] Pointer bindings with modifiers
- [x] XKB keybinding support

---

## In Progress

### IPC Expansion
- [ ] `get-state` - Return current mode, layout, tags, focused window
- [ ] `reload-config` - Hot reload without restart

---

## Planned

### Window Management
- [ ] Window rules (auto-float, tag assignment, workspace)
- [ ] Scratchpad (toggle-able named floating windows)
- [ ] Sticky windows (visible on all tags)
- [ ] Window cycling (alt-tab style)

### Configuration
- [ ] Per-output settings (layout, scale, tags)
- [ ] Startup programs (autostart on WM init)
- [ ] Config validation with helpful errors

### IPC & Integration
- [ ] Status bar events (for waybar/polybar)
- [ ] Window list query
- [ ] Active window change notifications
- [ ] Layout change notifications

### Delta Popup
- [ ] Dynamic content (window list, layout picker)
- [ ] Search/filter in menus
- [ ] Animations (fade in/out)
- [ ] Icons support

### Session
- [ ] Save/restore window positions
- [ ] Named workspace presets

---

## Ideas / Maybe

- [ ] Tiling algorithm plugins
- [ ] Lua/wasm scripting for custom actions
- [ ] Built-in screenshot/screen recording integration
- [ ] Gesture support for touchpads
- [ ] PipeWire integration for audio feedback

---

## Technical Debt

- [ ] Popup surface caching (currently recreated each show)
- [ ] Config error reporting to user (currently silent/logged)
- [ ] Test coverage for config parsers
- [ ] Documentation for config format

---

## Version History

### v0.1 (current)
- Basic window management via kwm
- Delta popup with chord navigation
- IPC socket control
- HiDPI scaling support
- Doom-style configuration
