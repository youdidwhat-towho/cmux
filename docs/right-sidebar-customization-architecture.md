# Right Sidebar Customization Architecture

Last updated: April 21, 2026

## Goal

Make the right sidebar fully customizable while preserving cmux's current terminal latency and focus behavior.

The first target should be a host-owned panel registry that can show built-in panels, config-defined panels, and out-of-process extension panels. ExtensionKit is useful for native third-party UI and should be the advanced plug-in lane after simpler customization works.

## Current State

The right sidebar is implemented in `Sources/RightSidebarPanelView.swift`.

Current behavior:

1. `RightSidebarMode` identifies the built-in `files` and `sessions` panels.
2. `RightSidebarPanelView` renders a descriptor-backed mode bar and can show built-in, markdown, web, and command-output panels.
3. `FileExplorerState.selectedPanelId` persists the selected panel with `UserDefaults` key `rightSidebar.selectedPanelId`, while migrating the legacy `rightSidebar.mode` value.
4. `ContentView.terminalContentWithSidebarDropOverlay` mounts the sidebar on the trailing side, controls visibility by width, and keeps the view tree stable to avoid transition churn.

This shape now supports host-owned customization from `settings.json`. ExtensionKit remains the next step for native third-party UI because panel lifecycle, permissions, and XPC contracts need a stricter process boundary than config panels.

## Framework Roles

cmux currently targets macOS 14. ExtensionFoundation and ExtensionKit are available for this target.

### ExtensionFoundation

ExtensionFoundation is the host and extension model.

Use it when cmux wants to define extension points, discover matching app extensions, launch them, and communicate over XPC. Apple positions it for apps that want other developers to extend the app or for code that should run outside the main process.

For cmux, ExtensionFoundation would own:

1. `AppExtensionPoint` definitions, for example `com.manaflow.cmux.right-sidebar-panel`.
2. `AppExtensionPoint.Monitor` discovery for installed and enabled sidebar extensions.
3. `AppExtensionIdentity` selection.
4. `AppExtensionProcess` lifecycle for non-UI work and XPC connections.
5. Invalidation and interruption handling when an extension exits, crashes, or is reloaded.

Official docs:
1. https://developer.apple.com/documentation/extensionfoundation
2. https://developer.apple.com/documentation/extensionfoundation/adding-support-for-app-extensions-to-your-app
3. https://developer.apple.com/documentation/extensionfoundation/discovering-app-extensions-from-your-app

### ExtensionKit

ExtensionKit is the UI embedding layer.

Use it when cmux wants an extension to provide native UI inside the right sidebar. The host app embeds an `EXHostViewController`, configured with an `AppExtensionIdentity` and scene ID. SwiftUI hosts this through `NSViewControllerRepresentable`.

For cmux, ExtensionKit would own:

1. A sidebar panel host view backed by `EXHostViewController`.
2. Scene selection, for example `RightSidebarPanel`.
3. Optional scene-specific XPC setup for panel interaction.
4. Switching or recreating host controllers when the user selects another extension panel.

Official docs:
1. https://developer.apple.com/documentation/extensionkit/appextensionscene
2. https://developer.apple.com/documentation/extensionkit/including-extension-based-ui-in-your-interface

### XPC

XPC is the process boundary and message transport.

Use it for host to extension communication, permissioned actions, and crash containment. The host defines the protocol. The extension receives snapshots and sends actions back. The extension should never get direct access to cmux's `ObservableObject` stores, terminal views, or app internals.

For cmux, XPC should carry:

1. Sidebar context snapshots, such as selected workspace, focused surface, cwd, theme, remote status, git state, ports, and notification summary.
2. Host actions, such as open file, create split, focus surface, run command with trust policy, set sidebar metadata, or request browser navigation.
3. Extension events, such as selection changed, reload requested, panel height preference changed, or error surfaced.

Use value types for messages. Keep the API narrow and versioned.

Official docs:
1. https://developer.apple.com/documentation/xpc
2. https://developer.apple.com/documentation/foundation/nsxpcconnection

## Dynamic Reload Answer

Yes, cmux can support dynamic reload. The reload contract should be controlled teardown and recreation.

What can reload dynamically:

1. The list of installed app extensions can update while cmux is running through `AppExtensionPoint.Monitor` observation.
2. A selected ExtensionKit UI can be replaced by changing the `EXHostViewController` configuration or by destroying and recreating the host controller.
3. XPC connections can be invalidated and recreated.
4. Config-defined panels can reload immediately from watched JSON files.
5. Web or markdown panels can reload their content without restarting cmux.

What should not be promised:

1. Arbitrary SwiftUI code hot reload inside the main cmux process.
2. Loading unsigned native bundles directly into cmux.
3. Keeping old extension state alive after the extension binary changes.
4. Reloading an extension without closing all live XPC/UI connections to the old process.

Apple's process model can reconnect to an already running extension process or launch a new one as needed. `AppExtensionProcess.invalidate()` releases the host's reference. The system may keep the extension alive until all active connections close. cmux should model reload as:

1. mark panel reloading
2. remove the current host view
3. invalidate host-owned process and XPC handles
4. rebuild process or host view from the latest identity/config
5. restore persisted panel selection and serializable extension state if supported

## Recommended cmux Architecture

### 1. Add a host-owned panel registry

Replace the hardcoded `RightSidebarMode` enum with a registry.

Core model:

```swift
struct RightSidebarPanelDescriptor: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var symbolName: String
    var source: RightSidebarPanelSource
    var capabilities: Set<RightSidebarPanelCapability>
}

enum RightSidebarPanelSource: Equatable, Sendable {
    case builtIn(BuiltInRightSidebarPanel)
    case config(RightSidebarConfigPanel)
    case appExtension(RightSidebarExtensionPanel)
}
```

The registry owns ordering, visibility, labels, icons, selected panel, and reload state. Built-in panels become descriptors instead of enum cases.

### 2. Move persistence to cmux settings

Keep `UserDefaults` compatibility as a migration path. Store customizable sidebar state in `~/.config/cmux/settings.json`.

Suggested shape:

```json
{
  "rightSidebar": {
    "visible": true,
    "width": 260,
    "selectedPanel": "builtin.files",
    "panels": [
      { "id": "builtin.files", "enabled": true },
      { "id": "builtin.sessions", "enabled": true },
      { "id": "config.project-status", "enabled": true }
    ]
  }
}
```

### 3. Support low-friction custom panels first

Before native extensions, ship config-defined panels because they cover most user customization and reload instantly.

Useful panel kinds:

1. Markdown panel from a file path.
2. Web panel from a local or remote URL.
3. Command output panel with a refresh policy and trust prompt.
4. JSON status panel using the existing socket metadata concepts.

Example:

```json
{
  "rightSidebar": {
    "panels": [
      {
        "id": "project.tasks",
        "title": "Tasks",
        "icon": "checklist",
        "kind": "command",
        "command": "task list --json",
        "refresh": "onFocusOrFileChange"
      }
    ]
  }
}
```

This gives users a customizable sidebar without requiring Apple extension packaging, signing, or system enablement.

### 4. Add ExtensionKit as the native plug-in lane

After the registry exists, add native app extension support behind one panel source type.

Host side:

1. Define `com.manaflow.cmux.right-sidebar-panel` with `UserInterface(true)`.
2. Monitor matching extension identities.
3. Convert enabled identities into registry descriptors.
4. Embed the selected identity with an `EXHostViewController`.
5. Connect a versioned XPC API for snapshots and actions.

Extension side:

1. Bind to cmux's extension point.
2. Provide a scene named `RightSidebarPanel`.
3. Implement the XPC protocol declared by cmux's extension SDK.
4. Declare requested capabilities in metadata.

### 5. Keep the sidebar snapshot-only

The right sidebar already has performance-sensitive SwiftUI lists. Any custom panel contract must preserve that boundary.

Rules:

1. Built-in panels may keep existing stores.
2. Config and extension panels receive immutable snapshots.
3. Rows below list boundaries receive value snapshots and action closures only.
4. Extensions call back through XPC actions instead of mutating app state.
5. High-frequency events are coalesced off-main before UI updates.

### 6. Version the host API

The extension API should start tiny.

Suggested v1 host-to-extension messages:

1. `hello(hostVersion, apiVersion, capabilities)`
2. `contextDidChange(RightSidebarContextSnapshot)`
3. `themeDidChange(RightSidebarThemeSnapshot)`
4. `reload(reason)`

Suggested extension-to-host actions:

1. `openURL`
2. `openFile`
3. `runCommand`
4. `focusWorkspace`
5. `focusSurface`
6. `setStatus`
7. `showError`

Every action needs an explicit allowlist and trust behavior.

## Implementation Milestones

### M1: Native registry, no new user-facing extension system

1. Introduced `RightSidebarPanelRegistry`.
2. Converted Files and Sessions into built-in descriptors.
3. Kept the existing mode bar UI and render descriptors.
4. Preserved `rightSidebar.mode` migration.
5. Added unit tests for settings parsing and invalid-panel filtering.

### M2: Config-defined panels

1. Added settings schema for right sidebar panel order and enablement.
2. Added markdown, web, and command-output panel sources.
3. Reload panels dynamically from the existing settings-file watcher.
4. Add trust prompts for command panels.
5. Added docs for `settings.json`.

### M3: ExtensionKit prototype

1. Add the app extension point.
2. Add `EXHostViewController` SwiftUI wrapper.
3. Add a sample bundled extension.
4. Add mock XPC protocol and context snapshots.
5. Test selection, crash handling, and reload teardown.

### M4: Third-party extension SDK

1. Publish a small Swift package with the XPC interfaces and Codable snapshot models.
2. Add an extension management UI using Apple's enable/disable surface where possible.
3. Add capability prompts.
4. Add compatibility checks for API versions.

## Decision

Use a layered model:

1. Registry first.
2. Config-defined panels second.
3. ExtensionKit plus ExtensionFoundation third.
4. XPC for all native extension communication.

This gives cmux dynamic customization quickly while reserving native out-of-process UI for signed extensions that need deeper integration.
