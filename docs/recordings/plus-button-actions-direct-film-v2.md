# Plus Button Actions Direct Film v2

Task source: https://github.com/manaflow-ai/cmux/pull/3348

## Setup
- Target checkout reference: `loader/recording-plus-button-actions-direct-film-v2`
- Reload tag used: `pfilm4`
- App path: `/Users/runner/Library/Developer/Xcode/DerivedData/cmux-pfilm4/Build/Products/Debug/cmux DEV pfilm4.app`

## Config written
`$HOME/.config/cmux/cmux.json` was set to the provided configuration for:
- `demo-shell` command action (`printf 'right click menu action works\n'; exec /bin/zsh -l`)
- `demo-workspace` command action
- `newWorkspace` context menu entries:
  - `New Terminal`
  - separator
  - `Demo Shell`
  - `Demo Workspace`
- `commands`: `Demo Workspace`

## Reproduction steps performed
1. Build and launch tagged app:
   - `./scripts/reload.sh --tag pfilm4 --launch`
2. Approved computer-use access:
   - `./.cmux-loader/approve-computer-use-app "/Users/runner/Library/Developer/Xcode/DerivedData/cmux-pfilm4/Build/Products/Debug/cmux DEV pfilm4.app"`
3. Position app window:
   - `./.cmux-loader/set-app-window-frame "cmux DEV pfilm4" 20 90 1500 950 2`
4. Removed stale target-window files:
   - `rm -f "${CMUX_LOADER_RUNNER_DIR:-../.runner}/target-window-id" .runner/target-window-id ../.runner/target-window-id`
5. Prepared video dir:
   - `videos_dir="${CMUX_LOADER_RUNNER_DIR:-../.runner}/videos"`
   - `mkdir -p "$videos_dir"`
6. Captured preflight (8s):
   - `nohup screencapture -x -v -C -k -V8 "$videos_dir/preflight.mov" > "$videos_dir/preflight.log" 2>&1 &`
7. Ran reproduction capture (60s):
   - `nohup screencapture -x -v -C -k -V60 "$videos_dir/repro.mov" > "$videos_dir/repro.log" 2>&1 &`
8. Used computer-use to:
   - Hover pointer over the titlebar plus/new-workspace button
   - Right-click it and leave menu open
   - Select `Demo Shell` from the context menu
   - Waited for `right click menu action works` terminal output
   - Return pointer to plus button and click normally
   - Verify `New tab` browser surface remains visible

## Capture results
- `videos.tsv` entries in `${CMUX_LOADER_RUNNER_DIR:-../.runner}/videos/videos.tsv`:
  - `preflight`
    - file: `/Users/runner/work/cmux-loader/cmux-loader/.runner/videos/preflight.mov`
    - status: `ok`
    - started: `2026-04-30T10:26:48Z`
    - stopped: `2026-04-30T10:26:57Z`
  - `repro`
    - file: `/Users/runner/work/cmux-loader/cmux-loader/.runner/videos/repro.mov`
    - status: `ok`
    - started: `2026-04-30T10:27:03Z`
    - stopped: `2026-04-30T10:28:03Z`

## Repro duration
- `repro` capture duration: 60 seconds

## Milestone verification from extracted frames
- 2s / 6s / 10s frame extraction confirms the plus-button context menu appears with entries including `New Terminal`, `Demo Shell`, and `Demo Workspace`.
- 16s and 24s OCR confirms terminal text contains `right click menu action works`, verifying the Demo Shell action executed.
- 34s, 44s, and 54s OCR confirms the browser surface is visible and named `New tab` (with browser UI/omnibar present).

## Environment / blockers
- `ffmpeg` is not installed in the runner path, so frame extraction was done via temporary Swift + AVFoundation scripts (`/tmp/extract_frames.swift`).
- No blockers prevented completion of preflight or repro captures.
