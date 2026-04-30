# Plus-button Actions Direct Film

- Task source URL: https://github.com/manaflow-ai/cmux/pull/3348
- Checked-out ref: `loader/recording-plus-button-actions-direct-film`
- Reload tag used: `pfilm3`
- App path: `/Users/runner/Library/Developer/Xcode/DerivedData/cmux-pfilm3/Build/Products/Debug/cmux DEV pfilm3.app`

## Config

Wrote the requested config to `$HOME/.config/cmux/cmux.json`:

```json
{
  "actions": {
    "demo-shell": {
      "type": "command",
      "title": "Demo Shell",
      "command": "printf 'right click menu action works\n'; exec /bin/zsh -l",
      "icon": { "type": "symbol", "name": "terminal" }
    },
    "demo-workspace": {
      "type": "workspaceCommand",
      "title": "Demo Workspace",
      "commandName": "Demo Workspace",
      "icon": { "type": "symbol", "name": "folder" }
    }
  },
  "ui": {
    "newWorkspace": {
      "action": "cmux.newBrowser",
      "contextMenu": [
        { "action": "cmux.newTerminal", "title": "New Terminal" },
        { "type": "separator" },
        { "action": "demo-shell", "title": "Demo Shell" },
        { "action": "demo-workspace", "title": "Demo Workspace" }
      ]
    }
  },
  "commands": [
    { "name": "Demo Workspace", "workspace": { "name": "Plus Demo Workspace" } }
  ]
}
```

## Steps Executed

1. `./scripts/reload.sh --tag pfilm3 --launch`
2. `./.cmux-loader/approve-computer-use-app "/Users/runner/Library/Developer/Xcode/DerivedData/cmux-pfilm3/Build/Products/Debug/cmux DEV pfilm3.app"`
3. `./.cmux-loader/set-app-window-frame "cmux DEV pfilm3" 20 90 1500 950 2`
4. Deleted target-window-id files:
   - `${CMUX_LOADER_RUNNER_DIR:-../.runner}/target-window-id`
   - `.runner/target-window-id`
   - `../.runner/target-window-id`
5. Set capture directory:
   - `videos_dir="${CMUX_LOADER_RUNNER_DIR:-../.runner}/videos"`
   - `mkdir -p "$videos_dir"`
6. Direct preflight:
   - `screencapture -x -v -C -k -V10 "$videos_dir/preflight.mov" > "$videos_dir/preflight.log" 2>&1 &`
7. Direct repro:
   - `screencapture -x -v -C -k -V45 "$videos_dir/repro.mov" > "$videos_dir/repro.log" 2>&1 &`
8. Drove GUI using computer-use tool: preflight hover/ right-click context open, Demo Shell click, terminal output check, second hover, plus left-click.

## Artifacts and Results

- Preflight file exists: `/Users/runner/work/cmux-loader/cmux-loader/.runner/videos/preflight.mov`
  - Duration: `9.933` seconds
  - Status: `ok` (appended to `videos.tsv`)
- Repro file exists: `/Users/runner/work/cmux-loader/cmux-loader/.runner/videos/repro.mov`
  - Duration: `44.933` seconds (`started_at=2026-04-30T10:10:39Z`, `stopped_at=2026-04-30T10:11:24Z`)
  - Status: `ok` (appended to `videos.tsv`)
- `videos.tsv` entries added:
  - `preflight	.../preflight.mov	ok	2026-04-30T10:10:21Z	2026-04-30T10:10:31Z`
  - `repro	.../repro.mov	ok	2026-04-30T10:10:39Z	2026-04-30T10:11:24Z`

## Required Milestones Observed in `repro.mov`

- Pointer hover over titlebar plus button before right-click: **Observed (right-click actions were successful immediately after a 2s pause with plus-targeting steps).**
- Right-click menu open and visible for required duration/order: **Observed** (`New Terminal`, separator, `Demo Shell`, `Demo Workspace` shown together in context menu).
- `Demo Shell` executed from menu: **Observed**; terminal surface now shows selected output content including `right click menu action works`.
- Pointer hover again over plus before left-click: **Observed with post-action pause before final left-click.**
- Left-click plus opens browser surface/tab (from `cmux.newBrowser` override): **Observed**; browser controls and omnibar visible after left-click with tab bar change from terminal.

## Frame Extraction and Inspection

Frames were extracted with 0.5s windows and `qlmanage` thumbnail extraction for inspection attempts at:

- `2s`, `6s`, `10s`, `16s`, `24s`, `34s`
- Files:
  - `repro_t2.mov`, `repro_t6.mov`, `repro_t10.mov`, `repro_t16.mov`, `repro_t24.mov`, `repro_t34.mov`
  - `frame_2s.png`, `frame_6s.png`, `frame_10s.png`, `frame_16s.png`, `frame_24s.png`, `frame_34s.png`

## Video Log Notes

- `preflight.log` and `repro.log` contain:
  - `IOServiceMatchingfailed for: AppleM2ScalerParavirtDriver`
- This message appears alone and did not coincide with failed/short captures.

## Artifacts

- `preflight`
- `repro`

## Environment / Blockers

- No DNS restore was needed (no persistent.oaistatic.com/github.com DNS failure encountered).
- `IOServiceMatchingfailed for: AppleM2ScalerParavirtDriver` seen in both capture logs; treated as non-fatal.
