# Mosaic

Modern terminal runtime for iOS. Native rendering, SSH + Mosh, no tmux required.

## Setup

```bash
chmod +x setup.sh && ./setup.sh
```

Then open `Mosaic.xcodeproj` and build.

## Dev Docs

- [`CLAUDE.md`](CLAUDE.md) — Claude Code instructions and Phase 1 build spec
- [`Docs/design-doc.md`](Docs/design-doc.md) — Full product design document
- [`Docs/technical-decisions.md`](Docs/technical-decisions.md) — All technical decisions and rationale

## Architecture

```
TerminalConnection (protocol)
  ├── SSHConnection  (NMSSH)
  └── MoshConnection (mosh-apple)
        ↓ outputStream
RendererRegistry
  ├── DockerPsRenderer
  ├── GitStatusRenderer
  ├── FileListRenderer
  └── ... (20+ renderers)
        ↓ RendererResult
SessionView
  ├── OutputBlock (.native) → NativeBadge + renderer SwiftUI view
  └── OutputBlock (.raw)    → monospace Text
```
