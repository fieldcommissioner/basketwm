# Basket

A doom-style window manager for River. Opinionated defaults, layered configuration, chord-based menus.

Built by an AI (Claude) with human guidance. [See CONTRIBUTING.md for the full story.](./CONTRIBUTING.md)

## Philosophy

**Doom Emacs for window management.** Sane defaults that work out of the box. Friendly to newcomers who just want tiling. Unrestricted for ricers who want total control.

- **Defaults** - Works immediately, no config required
- **Delta** - Which-key style popup for discoverability
- **Overrides** - Unbind anything, rebind everything

## Features

- **Layouts**: tile, monocle, scroller, floating
- **Tags**: Real tags (not workspaces) with per-tag layouts
- **Modes**: lock, default, floating, passthrough (vim-style modal bindings)
- **Delta popup**: Chord tree navigation with live hints
- **HiDPI**: Compositor-level scaling via wlr-output-management
- **IPC**: Unix socket control for scripting (`basketholder`)
- **Swallow**: Terminal windows swallow spawned GUI apps

## Requirements

- Zig 0.15+
- River 0.4.x (with river-window-management-v1)
- fcft (font rendering)
- pixman

## Quick Start

```bash
# Build
zig build

# Run (inside River session)
basket

# Or with River autostart
# ~/.config/river/init:
basket &
```

Press `Super` to open the delta popup. Press keys shown to navigate or execute.

## Configuration

```
~/.config/basket/
├── theme.zon      # Borders, gaps, colors, scale
├── config.zon     # Popup font, theme preset, position
├── basket.zon     # Keybinding overrides
├── delta.zon      # Chord tree root
└── +window.zon    # Module injection (merges at 'w' key)
```

See [docs/](./docs/) for detailed configuration guide (WIP).

### Example theme.zon

```zig
.{
    .border_width = 3,
    .border_color_focus = 0xffc777ff,
    .border_color_unfocus = 0x828bb8ff,
    .tile_inner_gap = 8,
    .tile_outer_gap = 6,
    .scale = 2.0,  // HiDPI
}
```

### Example basket.zon (keybind overrides)

```zig
.{
    .disable_defaults = false,
    .unbinds = .{
        .{ .key = "q", .modifiers = .{ .super = true } },  // remove Super+Q
    },
    .binds = .{
        .{ .key = "Return", .modifiers = .{ .super = true }, .action = "spawn alacritty" },
    },
}
```

## IPC

Control basket from scripts via `basketholder`:

```bash
# Using socat
echo "focus next" | socat - UNIX-CONNECT:$XDG_RUNTIME_DIR/basket.sock
echo "layout monocle" | socat - UNIX-CONNECT:$XDG_RUNTIME_DIR/basket.sock
echo "list" | socat - UNIX-CONNECT:$XDG_RUNTIME_DIR/basket.sock
```

Commands: `quit`, `restart`, `close`, `popup`, `hide-popup`, `focus`, `swap`, `layout`, `tag`, `mode`, `spawn`, and more. Run `list` for full reference.

## Documentation

- [ROADMAP.md](./ROADMAP.md) - Project status and planned features
- [CONTRIBUTING.md](./CONTRIBUTING.md) - How this was built, how to contribute
- [docs/dev/ARCHITECTURE.md](./docs/dev/ARCHITECTURE.md) - Code structure for developers

## Credits

- **River** - The Wayland compositor we build on
- **kwm** - The window management core we forked from
- **Doom Emacs** - The UX philosophy we borrowed
- **Claude** - The AI that wrote most of this code
- **Ben** - The human who made it happen

## License

MIT
