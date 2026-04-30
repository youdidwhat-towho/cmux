# cmux Launch Smoke (DNS Fix)

## Repro Steps Attempted
1. Built and launched tagged app:
   - `./scripts/reload.sh --tag recsmk --launch`
   - App path from output: `/Users/runner/Library/Developer/Xcode/DerivedData/cmux-recsmk/Build/Products/Debug/cmux DEV recsmk.app`
2. Approved computer-use access for the launched app:
   - `./.cmux-loader/approve-computer-use-app "/Users/runner/Library/Developer/Xcode/DerivedData/cmux-recsmk/Build/Products/Debug/cmux DEV recsmk.app"`
3. Sized the app window:
   - `./.cmux-loader/set-app-window-frame "cmux DEV recsmk" 20 90 1500 950 2`
4. Started required recording:
   - `./.cmux-loader/record-video start repro 180`
5. Used computer-use with app `com.cmuxterm.app.debug.recsmk`:
   - Fetched app state and interacted with app window.
   - Focused/selected terminal-related UI node 21 (Terminal content area) and issued typing actions:
     - `echo cmux cloud recording smoke OK`
     - Return key
6. Stopped recording:
   - `./.cmux-loader/record-video stop repro`

## Results
- cmux launched: **Yes** (tagged `cmux DEV recsmk` appeared and remained running).
- computer-use interaction: **Yes** (approval recorded; app was brought to front and interacted with).
- video artifact name: **`repro`** (`/Users/runner/work/cmux-loader/cmux-loader/.runner/videos/repro.mov`)

## Blockers / Environment Notes
- Repeated CUA synchronization responses (`"The user is still interacting..."`) occurred between rapid action calls, so each action required a re-query via `get_app_state` before the next.
- CUA focus metadata stayed as `focused UI element is 0 standard window`, so terminal input confirmation was not observable from the accessibility tree after typing actions.
- Runner macOS scrollbar context from task context: `AppleShowScrollBars=unset`.
