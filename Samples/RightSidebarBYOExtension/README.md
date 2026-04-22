# cmux Right Sidebar BYO Extension Sample

This sample is a separate macOS app that carries a cmux right sidebar ExtensionKit extension.

The app installs like any other macOS app. Its embedded `.appex` declares the cmux extension point:

```text
com.cmuxterm.app.debug.extkit.right-sidebar-panel
```

The extension exposes the scene id that the current cmux host demo loads:

```text
cmux-right-sidebar-demo
```

Build and register it:

```bash
Samples/RightSidebarBYOExtension/build-and-register.sh
```

Then open the tagged cmux build, switch the right sidebar to `ExtensionKit`, click refresh, and choose `cmux BYO Sidebar Sample`.

The resulting bundle is written to:

```text
~/Library/Application Support/cmux/ExtensionSamples/RightSidebarBYOExtension/cmux BYO Sidebar Sample.app
```

During development the script uses `pluginkit -a` to register the `.appex` directly. A production version would be distributed as a signed app whose containing bundle installs the extension through normal LaunchServices and PlugInKit registration.
