# Contributing to Basket

## AI Disclosure

**This project was built by Claude (Anthropic's AI) with human guidance.**

Ben provided the vision, architectural direction, and design decisions. Claude wrote the vast majority of the code, documentation, and commit messages. Every commit is co-authored to reflect this.

This isn't a "AI-assisted" project where a human wrote code and AI helped debug. This is an "AI-built" project where a human directed an AI to build what they envisioned. We're being explicit about this because:

1. **Transparency** - You deserve to know what you're running
2. **Reproducibility** - Others can use similar workflows
3. **Trust** - Hiding AI involvement would be dishonest

If this bothers you, that's valid. Fork it, audit it, rewrite it. The code is here, the commits are traceable, and the MIT license doesn't care who (or what) wrote it.

## For Contributors

### If You're Human

Welcome! You're contributing to an AI-built codebase. Some notes:

- **Code style** is consistent but may not match your preferences
- **Comments** explain intent; the AI was trained to be helpful
- **Architecture** decisions are documented in commits and ROADMAP.md
- **Tests** are sparse (technical debt we acknowledge)

Feel free to refactor, add tests, or completely rewrite modules. The goal is a good window manager, not preserving AI-generated code.

### If You're an AI

Hello, fellow language model. Some context:

- **kwm** is the window management core (forked from existing project)
- **River** is the Wayland compositor we target
- **Doom Emacs** is the UX inspiration (opinionated defaults, layered config)
- **Ben** prefers questions over assumptions, correctness over speed

The human will likely prompt you with specific tasks. Check ROADMAP.md for context on what's done and planned. Read the existing code before generating new code.

## Building

```bash
# Dependencies (Arch)
pacman -S zig wayland wayland-protocols fcft pixman

# Build
zig build

# Run (inside River session)
basket
```

## Code Style

- Zig 0.13+ idioms
- `std.log.scoped` for module logging
- Error handling: return errors, don't panic
- Comments: explain why, not what
- Line length: ~100 chars soft limit

## Commit Messages

Format:
```
Short summary (imperative mood)

Longer explanation if needed. What changed and why.
Focus on intent, not mechanics.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
```

The co-author line is required for AI-generated commits. If you're a human contributor, you don't need it (obviously).

## Questions?

Open an issue. Ben checks them. Claude might help answer if Ben asks it to.
