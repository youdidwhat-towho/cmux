# Iroh iPhone to Mac Demo

This prototype connects an iPhone app to a Mac terminal app with iroh.

The Mac runs a small Ratatui TUI that starts an iroh endpoint and prints an `EndpointTicket`. The iPhone app pastes that ticket and sends a request over a custom iroh ALPN. The Mac replies on the same QUIC stream and logs the request.

## Build the iOS Rust wrapper

```bash
./build-ios-xcframework.sh
```

This builds the Rust static library for device and simulator, then writes:

```text
iOS/IrohPhoneDemoPackage/Binaries/IrohPhoneMacFFI.xcframework
```

## Run the Mac TUI

```bash
cargo run --manifest-path rust/Cargo.toml --bin iroh-demo-tui
```

Copy the ticket shown in the TUI.

## Run the iPhone app

Open `iOS/IrohPhoneDemo.xcworkspace`, or build with XcodeBuildMCP after the XCFramework exists. Paste the Mac ticket into the app and tap `Ping Mac`.

The app returns the Mac response and round-trip time. The TUI logs the iPhone request.
