# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

This workspace is a testbed for Android edge-to-edge display behavior in Cordova apps, specifically how the CSS `env(safe-area-inset-*)` variables behave (or don't) across different `cordova-android` platform versions, the `AndroidEdgeToEdge` preference, and the `cordova-plugin-inset-injector` polyfill. It contains six independent Cordova projects that each represent one combination of these variables, so behavior can be compared side-by-side on real devices/emulators.

## Architecture

**One shared web app, many Cordova shells.** All six project directories contain a `www` symlink pointing to the single `www/` folder at the repo root (`<project>/www -> ../www`). There is no per-project web content — editing `www/index.html`, `www/css/style.css`, etc. changes the app for every project simultaneously. Never create a real (non-symlinked) `www` directory inside a project folder.

Each project is otherwise a standard Cordova project (`config.xml` + `package.json`), differing only in three axes:

| Project | cordova-android | `AndroidEdgeToEdge` | Extra plugin |
|---|---|---|---|
| `cordova-android14` | ^14.0.1 | n/a (pre-15, no e2e support) | — |
| `cordova-android14_statusbar` | ^14.0.1 | n/a | `cordova-plugin-statusbar` |
| `cordova-android15_e2e` | ^15.0.0 | `true` | — |
| `cordova-android15_e2e_insetinjector` | ^15.0.0 | `true` | `cordova-plugin-inset-injector` |
| `cordova-android15_no_e2e` | ^15.0.0 | `false` | — |
| `cordova-android15_no_e2e_insetinjector` | ^15.0.0 | `false` | `cordova-plugin-inset-injector` |

The naming convention is `cordova-android<version>[_e2e|_no_e2e][_statusbar|_insetinjector]`. If you add a new variant, follow this pattern, symlink its `www` to `../www`, and give it a distinct `id` in `config.xml`.

**Diagnostic page (`www/index.html`).** The page reads safe-area insets two independent ways and displays both for comparison:
- Native browser `env(safe-area-inset-*)` — measured by injecting a hidden 1px probe element with `padding: env(...)` and reading the computed style back.
- Plugin-provided values — read from the `--safe-area-inset-*` CSS custom properties on `document.documentElement`, only shown when `window.InsetInjector` exists (i.e. only in the `_insetinjector` projects). A `MutationObserver` on `documentElement`'s `style` attribute re-reads these when the plugin updates them.

Both sets of values are re-computed on `resize`, `orientationchange`, `screen.orientation.change`, and `deviceready`, and logged to the console as JSON for capture from device logs.

`www/css/style.css` applies insets to `#app` using a fallback chain: `var(--safe-area-inset-top, env(safe-area-inset-top, 0px))` — i.e. it prefers the plugin's CSS variable and falls back to the native `env()` value. This is the actual mechanism under test.

The page also has a status bar toggle button and a bare text input with no attached JS (its purpose isn't documented in code). The toggle button prefers `window.StatusBar` (the `cordova-plugin-statusbar` clobber) when present, otherwise falls back to `window.statusbar` (the cordova-android 15 built-in `SystemBarPlugin` clobber) when it looks like the real thing (`typeof window.statusbar.setBackgroundColor === "function"`), and each click both toggles visibility and sets a random background color. What that actually does differs by cordova-android version and installed plugin — this is itself a good example of the kind of cross-version behavior difference this workspace exists to surface:
- On **cordova-android 14** (`cordova-android14`, `cordova-android14_statusbar`), `window.statusbar` is the unmodified, standard, read-only legacy browser `BarProp` API (always `{ visible: true }` for a non-popup window) and has no `setBackgroundColor`, so the fallback branch is never taken. In `cordova-android14_statusbar`, `window.StatusBar` (capital) *is* present (from `cordova-plugin-statusbar`) and is used directly — `show()`/`hide()` and `backgroundColorByHexString()` genuinely control the native status bar. In plain `cordova-android14` (no plugin), neither branch applies and the button is a no-op.
- On **cordova-android 15** (unreleased as of this writing; `master` is `15.1.0-dev.0`), core now ships a built-in `SystemBarPlugin` whose JS shim clobbers `window.statusbar` with a writable object (`cordova-js-src/plugin/android/statusbar.js`) exposing `.visible` and `.setBackgroundColor()`. None of our cordova-android15 projects has `cordova-plugin-statusbar` installed, so all of them take the `window.statusbar` fallback branch; internally its setter calls native `exec(..., 'SystemBarPlugin', 'setStatusBarVisible'/'setStatusBarBackgroundColor', ...)`. Natively, `SystemBarPlugin.execute()` no-ops immediately whenever the `AndroidEdgeToEdge` preference is `true`. In practice: the button is a no-op in `cordova-android15_e2e`/`_e2e_insetinjector` (`AndroidEdgeToEdge=true`, native call short-circuits), but genuinely hides/shows and recolors the status bar in `cordova-android15_no_e2e`/`_no_e2e_insetinjector` (`AndroidEdgeToEdge=false`).

## Commands

`cordova` is not installed globally in this environment — it's a devDependency of each project, so invoke it with `npx` from inside that project's directory:

```bash
cd <project-dir>
npm install                      # install cordova + plugins from package.json
npx cordova platform add android # first-time setup; platforms/ is gitignored
npx cordova prepare android
npx cordova build android
npx cordova run android          # build + deploy to a connected device/emulator
```

There is no lint or test tooling configured in any project — the `test` script in a few `package.json` files is the default placeholder (`echo "Error: no test specified" && exit 1`), not a real test suite. Verification is manual: build, run on device/emulator, and read the on-screen/console inset values.

`platforms/` and `plugins/` directories are generated by Cordova and gitignored in every project — don't hand-edit or commit them; re-run `npx cordova prepare` after changing `config.xml` or plugin dependencies instead.
