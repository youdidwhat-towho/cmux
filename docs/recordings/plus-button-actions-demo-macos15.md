# plus-button-actions-demo-macos15

- Task source URL: https://github.com/manaflow-ai/cmux/pull/3348
- Checked out ref: `loader/recording-plus-button-actions-demo-macos15`
- Reload tag used: `pbtn15`
- App path used: `/Users/runner/Library/Developer/Xcode/DerivedData/cmux-pbtn15/Build/Products/Debug/cmux DEV pbtn15.app`

## Steps attempted
1. Wrote `/Users/runner/.config/cmux/cmux.json` with the provided JSON configuration.
2. Ran `./scripts/reload.sh --tag pbtn15 --launch`.
3. Ran `./.cmux-loader/approve-computer-use-app "/Users/runner/Library/Developer/Xcode/DerivedData/cmux-pbtn15/Build/Products/Debug/cmux DEV pbtn15.app"`.
4. Ran `./.cmux-loader/set-app-window-frame "cmux DEV pbtn15" 20 90 1500 950 2`.
5. Started recording: `./.cmux-loader/record-video start repro 180`.
6. In UI:
   - Right-clicked titlebar plus button (`titlebarControl.newTab`).
   - Confirmed menu order was `New Terminal`, `Demo Shell`, `Demo Workspace`.
   - Clicked `Demo Shell` and left terminal running command configured in `demo-shell`.
   - Left-clicked titlebar plus button and observed browser tab opening.
7. Stopped recording: `./.cmux-loader/record-video stop repro`.

## Result
- Configured left-click action worked: **Yes** (titlebar plus opened browser surface / browser tab via `cmux.newBrowser` override).
- Right-click menu appeared in configured order: **Yes** (`New Terminal`, separator, `Demo Shell`, `Demo Workspace`).
- Video artifact name: `repro`

## Environment notes
- Reload/approval logs indicated `cmuxterm.app.debug.pbtn15` launch and permissions were approved by helper scripts.
- No blockers encountered.
- DNS workaround script was not needed.
