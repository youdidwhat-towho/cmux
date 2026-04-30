# cmux launch smoke

## Repro Steps Attempted
- `./scripts/reload.sh --tag recsmk --launch`
- `./.cmux-loader/approve-computer-use-app "/Users/runner/Library/Developer/Xcode/DerivedData/cmux-recsmk/Build/Products/Debug/cmux DEV recsmk.app"`
- `./.cmux-loader/set-app-window-frame "cmux DEV recsmk" 20 90 1500 950 2`
- `./.cmux-loader/record-video start repro 180`
- Using computer-use on app `com.cmuxterm.app.debug.recsmk`:
  - Brought/focused app text entry area (main terminal content)
  - Typed `echo cmux cloud recording smoke OK`
- `./.cmux-loader/record-video stop repro`

## Outcome
- cmux launch: ✅ launched successfully with tagged app path from `reload.sh`.
- computer-use interaction: ✅ approved and interacted with the launched app; command was typed in terminal content area.
- video artifact name: `repro`

## Environment / Notes
- recorded file: `/Users/runner/work/cmux-loader/cmux-loader/.runner/videos/repro.mov`
- `record-video stop repro` returned `status=ok`
- macOS global scrollbar setting from runner context: `AppleShowScrollBars=unset`, `NSGlobalDomain AppleShowScrollBars=unset`
- no blockers encountered
