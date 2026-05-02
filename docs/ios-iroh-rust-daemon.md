# iOS iroh Rust daemon prototype

This PR starts a new iOS path that reuses the Rust `cmx` runtime instead of the Zig remote daemon from the previous iOS branch.

## Reused shape

The earlier `task-move-ios-app-into-cmux-repo` worktree is useful for the iOS project shape, split-view navigation, terminal sidebar model, signing setup, and dogfood scripts. It also proves that an iOS app belongs in this repository instead of a separate checkout.

The parts this path deliberately does not carry forward are the Zig daemon, localhost/Tailscale assumptions, direct WebSocket/SSH fallback, and Swift-owned terminal state. Those pieces were tied to the old daemon contract.

## Rust daemon path

The Rust `cmx` runtime from `$HOME/fun/cmux-cli` already has the core pieces this app needs:

- workspaces, spaces, panes, and terminal state
- a MessagePack protocol for TUI frame streaming, commands, layout, and native snapshots
- a TUI attach mode that streams the same ANSI frame model used by the Rust `cmx` terminal interface

The first production milestone is not the Swift sidebar model. It is iOS connecting as another `cmx` client and rendering the shared TUI interface through libghostty/GhosttyKit. The iOS client sends `Hello`, receives `PtyBytes`, sends `Input` and `Command`, and reconnects to the same Rust daemon state as the CLI/TUI.

After that works, the Swift app should move to Rust-owned state by using `HelloNative`, `NativeSnapshot`, `TerminalGridSnapshot`, `NativeInput`, `NativeLayout`, and `Command`. Swift should render native controls, but Rust owns the workspace, space, panel, tab, terminal, and reconnect lifecycle.

Current implementation status:

- iOS renders the terminal with actual libghostty/GhosttyKit.
- The iOS renderer has unit coverage for unchanged PTY byte forwarding, actual Ghostty surface creation, ANSI output rendering, and outbound typed input.
- iOS has a local Swift `cmx` MessagePack codec with unit coverage for the TUI wire contract plus native `HelloNative`, `NativeSnapshot`, and `TerminalGridSnapshot` decoding.
- iOS has the Stack/Rivet pairing auth frame model and HMAC proof algorithm. The Swift proof test shares the Rust bridge vector `w62sYb9esNfmw-GwP36Z2ooce7olwxryi3xdRWVRpHs`, so the eventual iroh client can prove possession of the Rivet-delivered secret before opening the cmx stream.
- Connected mode uses a real `cmx` WebSocket dev stream. iOS now requests `HelloNative` with `terminal_renderer = libghostty`, applies Rust-owned `NativeSnapshot` state to the workspace UI, sends `NativeInput` scoped to the selected tab, and sends `NativeLayout` for the visible terminal.
- Rust native mode now supports two renderer contracts: existing `server_grid` clients still receive `TerminalGridSnapshot`; iOS `libghostty` clients receive bounded PTY replay plus live `PtyBytes`, so actual libghostty/GhosttyKit owns terminal parsing, themes, colors, cursor state, and input echo.
- The simulator dogfood path connects to `cmx server --ws-bind 0.0.0.0:8787 --auth-token dev` with a direct development ticket and verifies typed input renders back through Ghostty.
- The home screen now uses an iMessage-style workspace inbox shell with node pins and full-width conversation rows. The data source is still demo state until Stack Auth and Rivet hive discovery land.
- The rail/resize bounds helper from the old iOS branch lives at `scripts/tui-terminal-bounds-check.sh`, and the Rust tmux dogfood suite verifies the helper tracks the maximum pane size after resize.
- Iroh bridge tickets can now include non-secret node metadata (`id`, `name`, `subtitle`, `kind`). iOS uses that metadata for the connected node row, falling back to the endpoint id until Stack Auth and Rivet hive discovery are wired.

The WebSocket route is a dev stepping stone so we can test the protocol and renderer composition before the iroh transport lands. It is not the production transport.

## iroh transport

`cmux-iroh-bridge` exposes a local `cmx` Unix socket over iroh with ALPN `/cmux/cmx/3`. The bridge prints a JSON ticket containing the iroh endpoint address and auth metadata, and the iOS app parses that ticket before connecting.

Tickets may also include node metadata for UI discovery. That metadata is intentionally non-secret and is not an authorization decision. Production auth still comes from Stack identity plus a Rivet-delivered pairing secret proven over the iroh stream before the bridge proxies the local `cmx` socket.

This is not SSH and not a WebSocket tunnel. The transport is iroh's QUIC endpoint with iroh discovery/relay behavior. The application protocol above that stream remains the `cmx` MessagePack protocol, starting with TUI mode for the first iOS sync milestone.

The current bridge defaults to iroh's N0 preset for discovery and relay behavior. It also supports `--relay disabled` for local tests and future self-managed environments. Production must make the discovery/relay policy explicit in settings before relying on it for customer traffic.

## Auth and RivetKit role

Stack Auth owns user identity. RivetKit carries the short-lived pairing control plane: pairing id, encrypted or otherwise protected secret material, device presence, invite/session metadata, and durable account-scoped connection records through actor state, key/value, or database APIs. The terminal stream stays peer-to-peer over iroh.

The bridge does not put the pairing secret in the iroh ticket. The ticket advertises the pairing id, Rivet endpoint, Stack project id, and expiration. A client signed in with Stack asks Rivet for the pairing secret, connects over iroh, receives a nonce, and proves possession with an HMAC before the bridge opens the local `cmx` socket. Direct unauthenticated tickets are only for explicit local development.

RivetKit docs that matter for that future step:

- https://rivet.dev/docs/actors/state
- https://rivet.dev/docs/actors/connections
- https://rivet.dev/docs/actors/events
- https://rivet.dev/docs/actors/keys
- https://rivet.dev/docs/clients/swift
- https://rivet.dev/docs/general/runtime-modes
- https://rivet.dev/docs/self-hosting/install

## Ghostty decision

The old iOS branch carried Ghostty changes for manual embedded I/O. After checking upstream Ghostty, those cmux-specific manual I/O API changes are still not available upstream.

The iOS app now renders terminal frames with actual libghostty/GhosttyKit, not `libghostty-vt`. The Swift surface feeds PTY bytes into Ghostty's parser, sends user input back through the same store path, and uses Ghostty theme/color rendering. The fork keeps cmux comments on the manual I/O and iOS rendering hooks so they can be removed if upstream Ghostty grows equivalent embedded APIs.

`libghostty-vt` remains useful on the Rust daemon side only for deriving structured native snapshots later. It should not be used as the iOS terminal renderer.
