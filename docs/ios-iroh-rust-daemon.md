# iOS iroh Rust daemon prototype

This PR starts a new iOS path that reuses the Rust `cmx` runtime instead of the Zig remote daemon from the previous iOS branch.

## Reused shape

The earlier `task-move-ios-app-into-cmux-repo` worktree is useful for the iOS project shape, split-view navigation, terminal sidebar model, signing setup, and dogfood scripts. It also proves that an iOS app belongs in this repository instead of a separate checkout.

The parts this path deliberately does not carry forward are the Zig daemon, localhost/Tailscale assumptions, direct WebSocket/SSH fallback, and Swift-owned terminal state. Those pieces were tied to the old daemon contract.

## Rust daemon path

The imported Rust tree under `rust/cmux-cli` already has the core pieces this app needs:

- workspaces, spaces, panes, and terminal state
- a MessagePack protocol for TUI frame streaming, commands, layout, and native snapshots
- `libghostty-vt` based terminal parsing in the daemon for native snapshots
- a TUI attach mode that streams the same ANSI frame model used by the Rust `cmx` terminal interface

The first production milestone is not the Swift sidebar model. It is iOS connecting as another `cmx` client and rendering the shared TUI interface through libghostty/GhosttyKit. The iOS client sends `Hello`, receives `PtyBytes`, sends `Input` and `Command`, and reconnects to the same Rust daemon state as the CLI/TUI.

After that works, the Swift app should move to Rust-owned state by using `HelloNative`, `NativeSnapshot`, `TerminalGridSnapshot`, `NativeInput`, `NativeLayout`, and `Command`. Swift should render native controls, but Rust owns the workspace, space, panel, tab, terminal, and reconnect lifecycle.

## iroh transport

`cmux-iroh-bridge` exposes a local `cmx` Unix socket over iroh with ALPN `/cmux/cmx/3`. The bridge prints a JSON ticket containing the iroh endpoint address and auth metadata, and the iOS app parses that ticket before connecting.

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

For the first TUI sync milestone, iOS should render the Rust `cmx` TUI frames with libghostty/GhosttyKit. That avoids Swift-owned terminal state and matches the CLI/TUI interface. For the later Swift-native app, we can either draw server-derived `TerminalGridSnapshot` cells directly or revisit Ghostty manual I/O if we need native Ghostty surface rendering with Rust-owned state.
