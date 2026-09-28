# Landing Demo

The **See Alera In Action** section of the landing home page (`landing/src/components/Product.astro`) is a live recreation of the Alera desktop app and the Android companion. It is drawn in HTML, CSS, and SVG from the app's own tokens, icons, agent marks, and copy, and played by a deterministic timeline. It is not a video and not a screen recording: every frame is computed from the storyboard, so the same time always draws the same picture.

The page says what the demo is under the player: the agent sessions are staged samples, and agent status hooks and push notifications, which are opt-in in the app, are shown turned on.

## What It Shows

Four chapters on one 89 second clock. The sample project is `storefront` on the host `Studio`, paired with a `Pixel 7a`; the pull request is `#128`.

| Chapter | Time | What happens |
|---|---|---|
| Start From A Prompt | 0 to 19 s | ⇧⌘N opens New Workspace in From Prompt mode. Create closes the dialog, the job card walks through the phases `background_setup_jobs.dart` runs, the new row appears in the sidebar without being selected, and "Workspace created" arrives once Claude has started. |
| Agents In Parallel | 19 to 40 s | ⌘D splits the pane and Codex starts in the new terminal. The sidebar switches to the agent summary, the status bar shows quotas, Resource Manager shows each terminal's cost, and Claude stops to ask for permission. |
| Answer From Your Phone | 40 to 60 s | The push opens the workspace on the phone, the phone takes the driver seat (the desktop pane narrows to the phone's columns under the driver banner), Enter answers Claude, and the desktop takes the terminal back. |
| Review And Ship | 60 to 89 s | ⇧⌘W closes the split and ⇧⌘G shows Source Control: stage, generate the commit message with AI Assist, commit, publish. The Pull Request tool drafts the title and description, a check fails, and Watch and Fix hands it back to Claude until the checks pass. |

## How It Is Built

- **Scene.** Astro components under `landing/src/components/demo/` render the whole stage at the app's logical size, 1720 × 900: the macOS window (1280 × 860, `desktop/`) and the Android phone (410 × 864 with a 390 × 844 screen, `mobile/`). `primitives/` holds what both share: icons, agent marks, state glyphs, spinners, and terminal panes. No part of the interface is an image; the only raster is the sidebar logo, copied from `assets/logo/`.
- **Styles.** `landing/src/styles/demo/`, scoped under `[data-alera-demo]` so they cannot reach the rest of the site. `tokens.css` mirrors `AleraTokens` and `terminal.css` the Alera Dark terminal theme; the other files follow the scene's parts. These are replicas of Flutter widgets, which is why they use plain CSS with the app's values instead of the landing's Tailwind tokens.
- **Storyboard.** `landing/src/data/demo/storyboard.ts` puts the chapters on the clock and pulls in one file per chapter (`storyboard-prompt.ts`, `storyboard-parallel.ts`, `storyboard-phone.ts`, `storyboard-review.ts`) plus the toasts, which share slots across chapters. Keys address scene nodes by their `data-demo-node` id and come in a few kinds: `states` set `data-state`, `shows` fade and collapse nodes, `texts` and `typing` write text, `reveals` show a terminal block line by line, `tweens` drive CSS custom properties, `camera` frames a node or a rectangle, `pointer` moves the mouse or a touch, `hud` shows the shortcut being pressed, and `beats` replace the chapter caption. `storyboard-keys.ts` holds the helpers that write them.
- **Engine.** `landing/src/scripts/demo/`. `timeline.ts` compiles and validates the storyboard, and its `frameAt(t, layout)` is a pure function, so seeking and playing reach the same frame. `camera.ts` picks the tier and fits a target in the viewport. `scene-binding.ts` measures the nodes once and applies a frame to the DOM. `player.ts` owns the clock and the controls.
- **Determinism.** Motion inside the scene, such as agent and check spinners, is a paused CSS animation positioned by `--demo-t`, the demo clock in milliseconds, so a seek draws the same angle as playback. Terminals scroll by whole rows, using the row height each screen declares (16.9 px on the desktop, 14.4 px on the phone).

## Playback Rules

- The player mounts when the section comes within 400 px of the viewport, because measuring the scene renders its frames once.
- It autoplays only when at least 35% of it is visible and reduced motion is not requested, pauses below 20% or when the tab is hidden, and never loops: it ends on a card with Replay.
- With reduced motion it does not autoplay and a chapter button jumps to that chapter's poster frame.
- The stage is `aria-hidden` and `inert`. The caption, the controls, and **Read The Demo As Text** carry the same story as text, and the transcript credits the icon sets.
- Three tiers frame the stage: `wide` at 1100 px and above shows all of it, `medium` from 720 px uses 16:10, and `compact` below 720 px uses 4:5 and follows the action with the compact targets in the camera keys. The camera never magnifies past 1.1x, so text is never blurrier than the app's.

## Where Each Value Comes From

| What | Demo file | App source | Guard |
|---|---|---|---|
| Colors, sizes, radii, durations | `styles/demo/tokens.css` | `lib/src/app/theme/alera_tokens.dart` | `demo tokens` |
| Agent spinner period | `--app-agent-spin` in `tokens.css` | `agent_run_spinner_scope.dart` | `demo tokens` |
| Desktop terminal colors and metrics | `styles/demo/terminal.css` | `terminal_theme_catalog.dart`, `alera_settings.dart` | `demo terminal theme` |
| Desktop icons | `components/demo/primitives/app-icons.ts` | `lib/src/design_system/icons/alera_icons.dart` | `demo icons` |
| Phone icons | `components/demo/primitives/mobile-icons.ts` | `mobile/lib/src/design_system/icons/alera_icons.dart` | `demo icons` |
| Lucide release | `@lucide/astro` in `landing/package.json` | `lucide_icons_flutter` in `pubspec.lock` | `demo icons` |
| Source control glyphs | `data/demo/codicons.ts`, `public/demo/fonts/alera-codicons.woff2` | `lib/src/design_system/icons/alera_codicons.dart` | `demo icons` |
| Agent marks | `landing/src/assets/demo/agents/` | `assets/agents/` | `demo icons`, byte for byte |
| Sidebar logo | `landing/public/demo/alera-logo-white.png` | `assets/logo/alera-logo-white.png` | `demo icons`, byte for byte |
| Quoted copy | `data/demo/app-copy.ts` | the `source` of each entry | `demo copy` |
| Shortcuts | `data/demo/shortcuts.ts` | `keyboard_action_definitions.dart` | `demo shortcuts` |
| Terminal glyphs | `data/demo/transcripts.ts` | the served JetBrains Mono subsets (`landing/src/data/font-coverage.json`) | `demo terminals` |
| File icons | `landing/src/assets/demo/file-icons/` | `vscode_material_icon_theme` (material-icon-theme 5.37.0) | none |
| Phone system and Material icons | `landing/src/assets/demo/material-icons/` | Flutter's Material icons | none |
| Phone terminal palette | `.phone-term` in `styles/demo/mobile-workspace.css` | the xterm default theme the phone keeps | none |
| Layout: rows, chips, panels, dialogs | the components and their CSS | the Flutter file named in each component's doc comment | none, compare side by side |

The guards are the `describe` blocks in `landing/src/data/demo/fidelity.test.ts`. The last one checks that `.github/workflows/landing-fidelity.yml` watches every app file those tests read.

## Keeping It Faithful

- A change to the app's tokens, icons, marks, logo, shortcuts, or any string in `app-copy.ts` must update the demo in the same change. `landing-fidelity.yml` runs the guards on pull requests that touch those sources, so drift fails there rather than on the landing page.
- A change to how a screen the demo draws is laid out is not caught by a test. When one lands, compare the demo side by side with the app (`make app-debug` on macOS and the Android APK) using the table above and the doc comment of the matching component, which names the widget it copies.
- The storyboard's own rules are in `landing/src/data/demo/storyboard.test.ts`: the chapters cover the clock in order, every node a key touches is declared by the scene, a reveal has one step per terminal line, and no caption uses an em dash.
- `landing/e2e/demo.spec.ts` and `landing/e2e/demo-mobile.spec.ts` cover playback, pausing from the control and when scrolled away, chapters, the end card, reduced motion, the accessibility tree, seeking the same time twice, and the compact tier.

## Capture Mode

`/?demo=capture` mounts the demo immediately, hides everything around the stage, never plays, and exposes `window.__aleraDemo` with the duration, the chapters, and an async `seek(t)` that resolves once the frame has been painted. It exists so a script can render exact frames of the demo.

## README Media

The repository README shows media rendered from the demo, never a screen recording: `assets/product/alera-demo.webp`, an animated cut of about 30 seconds, and one poster per chapter (`assets/product/demo-<chapter>.webp`, taken at the chapter's poster time, the same frame a chapter button shows under reduced motion). `landing/src/data/demo/demo-media.ts` holds the size, the frame rate, the cuts, and the 4 MB budget for the animation.

To render them again, from `landing/`:

```bash
bun run build
bun run media:demo
```

`scripts/render-demo-media.ts` serves `dist/`, opens the demo in capture mode at 1376 × 720 (the wide tier, so the camera frames it as on the site), seeks every frame at 10 fps, and writes the animation, the posters, and `assets/product/demo-media.json`. Set `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH` to reuse an installed Chromium. The output depends only on the build, not on the speed of the machine.

`demo-media.json` records a fingerprint of everything the media draw: the storyboard's keys, the chapter timing, and the render settings, but not the captions, which the media do not show. `landing/src/data/demo/demo-media.test.ts` fails when the storyboard changes without a new render, when the animation grows past its budget, and when the README stops showing one of the files. A visual change to the scene that leaves the storyboard alone does not fail it; render again when such a change shows in the cuts.
