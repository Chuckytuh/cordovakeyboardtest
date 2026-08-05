# Cordova Safe-Area Inset Testbed

This workspace is a test tool. It shows how the Android safe-area insets
behave in a Cordova app. It lets you compare the behavior across different
`cordova-android` versions and settings.

## Purpose

Android can show app content behind the system bars. This is the
edge-to-edge mode. The CSS `env(safe-area-inset-*)` values tell the app how
much space the system bars and the display cutout use.

The behavior is different for each `cordova-android` version. It is also
different for the `AndroidEdgeToEdge` setting and for the
`cordova-plugin-inset-injector` plugin.

This workspace has six Cordova projects. Each project is one combination of
these three items. You install and start the projects on a device. Then you
compare the inset values.

## How it works

All six projects use one web app. Each project has a `www` symlink. The
symlink points to the single `www/` folder in the root of the repository.

Do not make a real `www` folder in a project. If you change a file in
`www/`, the change applies to all six projects.

The diagnostic page (`www/index.html`) reads the safe-area insets in two
ways:

- It reads the browser `env(safe-area-inset-*)` values. It adds a hidden
  probe element to the page. Then it reads the computed padding.
- It reads the `--safe-area-inset-*` CSS variables from the plugin. It shows
  these values only when the plugin is present.

The page shows both sets of values. It reads the values again after each
rotation or resize. It also writes the values to the console log as JSON.

The CSS applies the plugin value first. If there is no plugin value, the CSS
applies the `env()` value.

## The six variants

| Project | cordova-android | AndroidEdgeToEdge | Extra plugin |
|---|---|---|---|
| `cordova-android14` | ^14.0.1 | not applicable (before 15) | — |
| `cordova-android14_statusbar` | ^14.0.1 | not applicable | `cordova-plugin-statusbar` |
| `cordova-android15_e2e` | ^15.0.0 | `true` | — |
| `cordova-android15_e2e_insetinjector` | ^15.0.0 | `true` | `cordova-plugin-inset-injector` |
| `cordova-android15_no_e2e` | ^15.0.0 | `false` | — |
| `cordova-android15_no_e2e_insetinjector` | ^15.0.0 | `false` | `cordova-plugin-inset-injector` |

The name pattern is
`cordova-android<version>[_e2e|_no_e2e][_statusbar|_insetinjector]`.

## Before you start

Install these tools:

- Node.js. The script uses `npx` for `cordova` and `native-run`.
- `agent-device`, version 0.19.1 or later. The `record` command needs it.
  Put it on the PATH.
- Python 3. The `record` command needs it.
- An Android device or emulator.

## The workspace script

Use `workspace.sh` to operate all the projects together. Give one command
and its arguments:

```
./workspace.sh <command> [args]
```

### Install the platforms

Type this command one time:

```
./workspace.sh platforms
```

The command installs the dependencies. It also adds the Android platform to
each project.

### Build the apps

Type:

```
./workspace.sh build
```

The command builds each project for Android.

### Show the device targets

Type:

```
./workspace.sh list-targets
```

The command shows the emulator and device targets for the `run` command.

### Start an app on a device

Give the target first. Give the project second.

```
./workspace.sh run <target> [project]
```

The command installs and starts the built app. If you do not give a project,
the command starts all the projects in sequence.

Example:

```
./workspace.sh run emulator-5554 cordova-android15_e2e
```

### Make a recording

The `record` command uses `agent-device` to operate the app. It saves one
video for each project to the `recordings/` folder.

Give the device first. Give the project second. Both are optional.

```
./workspace.sh record [device] [project]
```

The command does these steps for each project:

1. It starts the app.
2. It scrolls the page to the bottom and then to the top.
3. It taps the "Toggle Status Bar" button two times.
4. It taps the input field. This shows the on-screen keyboard.
5. It taps outside the input field. This closes the keyboard.
6. It turns the device 90 degrees counterclockwise to landscape.
7. It does steps 2 to 5 again.
8. It turns the device back to portrait.
9. It stops the recording.

If a variant is not on the device, the command deploys it first. Build the
variant before you do this.

If you do not give a device, the command records on each booted device. If
you do not give a project, the command records each installed variant.

The `record` command uses the `agent-device` device name (for example
`"Pixel 8 SDK 34"`). This name is different from the `native-run` target.

### Show the recording targets

Type:

```
./workspace.sh record-targets
```

The command shows the booted Android devices for the `record` command.

## Commands for one project

`cordova` is not a global tool. It is a devDependency of each project. Go
into the project folder. Use `npx`:

```
cd <project>
npm install
npx cordova platform add android
npx cordova prepare android
npx cordova build android
npx cordova run android
```

Do this again with `npx cordova prepare` after you change `config.xml` or a
plugin.

## How to read the results

Start a variant on a device. Look at the "Safe Area Insets" section on the
page:

- The "Browser env() Variables" values come from the WebView.
- The "Custom CSS Properties" values come from the plugin. They show only in
  the `_insetinjector` variants.

Compare the values of the different variants. Compare the values in portrait
and in landscape.

## Notes and limits

- Cordova makes the `platforms/` and `plugins/` folders. Git ignores them.
  Do not edit them by hand.
- Git ignores the video files in the `recordings/` folder.
- Android records the full screen. The video keeps the portrait frame. In
  landscape, the content shows in a band with black areas above and below.
- There is no automatic test tool. You do the checks by hand. Build the app,
  start the app, and read the values.
