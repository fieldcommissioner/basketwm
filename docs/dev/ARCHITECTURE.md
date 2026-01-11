# Basket Architecture

## Overview

Basket is a **Wayland window manager client** that runs on top of the **River compositor**. It doesn't manage windows directly - it tells River what to do via River's window management protocol.

```
┌─────────────────────────────────────────────────────┐
│                    River Compositor                  │
│  (handles rendering, input, Wayland protocol)       │
└─────────────────────────┬───────────────────────────┘
                          │ river-window-management-v1
                          │ wlr-output-management-v1
                          │ wlr-layer-shell-v1
┌─────────────────────────┴───────────────────────────┐
│                       Basket                         │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌───────────┐ │
│  │   kwm   │ │  popup  │ │   ipc   │ │  output   │ │
│  │ (core)  │ │ (delta) │ │ (sock)  │ │  config   │ │
│  └─────────┘ └─────────┘ └─────────┘ └───────────┘ │
└─────────────────────────────────────────────────────┘
```

## Module Map

### Core (`src/kwm/`)

The window management brain. Originally forked, heavily modified.

```
kwm/
├── context.zig      # Global state, River connection
├── seat.zig         # Input handling, keybindings, mode tracking
├── binding.zig      # Action enum, binding structs
├── runtime_bindings.zig  # Runtime-loaded bindings (vs compile-time)
├── window.zig       # Window state and operations
├── layout.zig       # Tile/monocle/scroller/float algorithms
└── types.zig        # Shared types (Direction, State, etc)
```

**Key concepts:**
- `Context` is the singleton holding River connection and global state
- `Seat` handles a single input seat (keyboard/pointer)
- `Action` is an enum of everything basket can do
- Modes filter which bindings are active

### Popup (`src/popup.zig`, `src/surface/`, `src/render/`, `src/tree/`)

The delta-style which-key popup menu.

```
popup.zig            # Popup state machine, keyboard handling
surface/
└── layer.zig        # wlr-layer-shell surface management
render/
├── menu.zig         # Menu rendering logic
├── fcft_font.zig    # Font rendering via fcft
├── font.zig         # Bitmap font fallback
└── buffer.zig       # Shared memory buffer management
tree/
└── navigation.zig   # Chord tree traversal
```

**Data flow:**
1. User presses leader key
2. `show_popup` action triggers `popup.show()`
3. LayerSurface creates wlr-layer-shell overlay
4. MenuRenderer draws current tree node
5. Keyboard events navigate tree or execute actions
6. `hide()` destroys the surface

### Config (`src/config/`)

Runtime configuration loading.

```
config/
├── loader.zig       # Delta tree loading (delta.zon, +modules)
├── settings.zig     # Global settings parser (config.zon)
├── basket_config.zig # Keybinding overrides (basket.zon)
└── zon.zig          # Low-level .zon parsing
```

**Config hierarchy:**
```
defaults.zig (compile-time)
    ↓ merged with
basket.zon (runtime unbind/rebind)
    ↓ stored in
runtime_bindings.zig
    ↓ loaded into
seat.xkb_bindings / seat.pointer_bindings
```

### IPC (`src/ipc/`)

Unix socket control interface.

```
ipc/
├── server.zig       # Socket listener, command dispatch
└── action_parser.zig # Text command → Action conversion
```

**Protocol:** Newline-delimited text commands over `$XDG_RUNTIME_DIR/basket.sock`

### Output Config (`src/output_config.zig`)

HiDPI scaling via wlr-output-management protocol.

Listens for output heads, applies scale from `theme.zon` when outputs are configured.

### Entry Point (`src/main.zig`)

1. Initialize allocator
2. Load theme.zon, apply to config vars
3. Initialize fcft font library
4. Load runtime keybindings
5. Connect to Wayland display
6. Bind River protocols
7. Initialize kwm.Context
8. Initialize popup (if layer-shell available)
9. Initialize IPC server
10. Enter event loop (poll Wayland + IPC fds)

## Data Flow Examples

### Keypress → Action

```
Wayland key event
    ↓
seat.zig: rwm_seat_listener
    ↓
Check mode, find matching XkbBinding
    ↓
binding.action matched
    ↓
seat.execute_action()
    ↓
context.spawn() / window.close() / etc
```

### IPC Command → Action

```
basketholder sends "focus next\n"
    ↓
server.zig: handleClient()
    ↓
action_parser.parse("focus next")
    ↓
Action{ .focus_iter = .{ .direction = .forward } }
    ↓
seat.unhandled_actions.append()
    ↓
context.rwm.manageDirty()
    ↓
seat.execute_action() on next manage cycle
```

### Config Loading

```
main.zig
    ↓
theme.load() → theme.zon → global_theme
theme.apply() → config.border_width, config.layout.*
    ↓
loadRuntimeBindings() → basket.zon + defaults.zig
    ↓ merged into
runtime_bindings.setXkbBindings()
    ↓
Seat.create() reads runtime_bindings
```

## Protocols Used

| Protocol | Purpose |
|----------|---------|
| `river-window-management-v1` | Window/output/tag control |
| `river-xkb-bindings-v1` | Keyboard binding registration |
| `river-layer-shell-v1` | Layer surface management |
| `wlr-layer-shell-v1` | Popup overlay surface |
| `wlr-output-management-v1` | HiDPI output scaling |
| `wp-viewporter` | Surface scaling |
| `wp-single-pixel-buffer-v1` | Efficient solid color surfaces |

## Build System

`build.zig` uses zig-wayland to generate Zig bindings from XML protocol definitions. Custom protocols live in `protocol/`.

## Testing

Sparse. Config parsers have some unit tests. Integration testing requires a running River session.

```bash
zig build test
```
