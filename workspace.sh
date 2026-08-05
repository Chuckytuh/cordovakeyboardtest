#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROJECTS=(
    cordova-android14
    cordova-android14_statusbar
    cordova-android15_e2e
    cordova-android15_e2e_insetinjector
    cordova-android15_no_e2e
    cordova-android15_no_e2e_insetinjector
)

usage() {
    cat <<EOF
Usage: $(basename "$0") <command> [args]

Commands:
  platforms                          npm install + add the android platform to every project
  build                              Build every project for android
  run <emulator-target> [project]    Deploy+launch built APK(s) on the given emulator/device
                                      <emulator-target> is passed to 'native-run --target'
                                      (AVD id, or a device/emulator serial from '$(basename "$0") list-targets')
                                      If [project] is omitted, runs all projects in sequence.
  list-targets                       Show available emulator/device targets (native-run --list)
  record [device] [project]          Drive the app with agent-device and save a screen recording
                                      per project to recordings/. The scripted flow: launch, scroll
                                      the page top-to-bottom, tap "Toggle Status Bar" twice, focus the
                                      input to raise the IME then tap outside to dismiss it, rotate 90deg
                                      anti-clockwise (landscape) and repeat, then stop.
                                      Any variant not yet installed is deployed first via 'run' (build it first).
                                      [device] is an agent-device android device name (default: every
                                      booted device; from '$(basename "$0") record-targets').
                                      [project] limits to one variant (default: every installed variant).
  record-targets                     Show booted android devices agent-device can record on

Examples:
  $(basename "$0") platforms
  $(basename "$0") build
  $(basename "$0") run Pixel_7_API_34
  $(basename "$0") run emulator-5554 cordova-android15_e2e
  $(basename "$0") record
  $(basename "$0") record "Pixel 8 SDK 34"
  $(basename "$0") record "Pixel 8 SDK 34" cordova-android15_e2e
EOF
}

is_known_project() {
    local candidate="$1"
    local known
    for known in "${PROJECTS[@]}"; do
        [[ "$known" == "$candidate" ]] && return 0
    done
    return 1
}

cmd_platforms() {
    for project in "${PROJECTS[@]}"; do
        echo "==> [$project] installing dependencies"
        (cd "$SCRIPT_DIR/$project" && npm install)
        if [[ -d "$SCRIPT_DIR/$project/platforms/android" ]]; then
            echo "==> [$project] android platform already added, skipping"
        else
            echo "==> [$project] adding android platform"
            (cd "$SCRIPT_DIR/$project" && npx cordova platform add android)
        fi
    done
}

cmd_build() {
    for project in "${PROJECTS[@]}"; do
        echo "==> [$project] building"
        (cd "$SCRIPT_DIR/$project" && npx cordova build android)
    done
}

find_apk() {
    local project="$1"
    local apk_dir="$SCRIPT_DIR/$project/platforms/android/app/build/outputs/apk/debug"
    local apk
    apk="$(find "$apk_dir" -maxdepth 1 -name '*.apk' -print -quit 2>/dev/null || true)"
    if [[ -z "$apk" ]]; then
        echo "error: no built APK found for $project (looked in $apk_dir)." >&2
        echo "       run '$(basename "$0") platforms' then '$(basename "$0") build' first." >&2
        return 1
    fi
    echo "$apk"
}

# Deploy+launch one project's built APK on a native-run target (AVD id or serial).
deploy_project() {
    local project="$1" target="$2"
    local apk
    apk="$(find_apk "$project")" || return 1
    echo "==> [$project] deploying $apk to target '$target'"
    npx native-run android --app "$apk" --target "$target"
}

cmd_run() {
    local target="${1:-}"
    local project="${2:-}"

    if [[ -z "$target" ]]; then
        echo "error: missing <emulator-target> argument" >&2
        usage
        return 1
    fi

    local targets=("${PROJECTS[@]}")
    if [[ -n "$project" ]]; then
        if ! is_known_project "$project"; then
            echo "error: unknown project '$project'" >&2
            printf '       known projects: %s\n' "${PROJECTS[*]}" >&2
            return 1
        fi
        targets=("$project")
    fi

    for p in "${targets[@]}"; do
        deploy_project "$p" "$target"
    done
}

cmd_list_targets() {
    npx native-run android --list
}

# --- agent-device recording ---------------------------------------------------
#
# The app is a single WebView whose DOM is only surfaced in the accessibility
# tree near the viewport, so the flow scrolls to bring the controls into view
# before touching them. The "Toggle Status Bar" button carries a stable DOM id
# (id="toggle-statusbar"); the input is a bare <input> with no id/label, so its
# tap point is read from the snapshot geometry each time. "landscape-left" is the
# 90deg anti-clockwise orientation.

AD_BIN="agent-device"

require_agent_device() {
    if ! command -v "$AD_BIN" >/dev/null 2>&1; then
        echo "error: 'agent-device' is not on PATH; install it before using 'record'." >&2
        return 1
    fi
}

app_id_for() {
    local project="$1"
    grep -oE 'id="[^"]+"' "$SCRIPT_DIR/$project/config.xml" | head -1 | sed -E 's/id="([^"]+)"/\1/'
}

# Booted android device names agent-device can drive (--device matches on name;
# names may contain spaces, so callers must iterate line-by-line).
booted_android_devices() {
    "$AD_BIN" devices --platform android --json 2>/dev/null | python3 -c '
import sys, json
d = sys.stdin.read(); s = d.find("{")
if s < 0: sys.exit(0)
obj, _ = json.JSONDecoder().raw_decode(d[s:])
for dev in obj.get("data", {}).get("devices", []):
    if dev.get("booted"):
        print(dev["name"])
'
}

# Resolve an agent-device device name to its native-run target (adb serial / AVD id).
device_target_for_name() {
    local name="$1"
    "$AD_BIN" devices --platform android --json 2>/dev/null | python3 -c '
import sys, json
name = sys.argv[1]
d = sys.stdin.read(); s = d.find("{")
if s < 0: sys.exit(1)
obj, _ = json.JSONDecoder().raw_decode(d[s:])
for dev in obj.get("data", {}).get("devices", []):
    if dev.get("name") == name:
        print(dev["id"]); break
else:
    sys.exit(1)
' "$name"
}

cmd_record_targets() {
    require_agent_device || return 1
    local devices
    devices="$(booted_android_devices)"
    if [[ -z "$devices" ]]; then
        echo "No booted android devices found. Start an emulator or connect a device first." >&2
        return 1
    fi
    echo "Booted android devices:"
    printf '  %s\n' "$devices"
}

app_installed() {
    local device="$1" app_id="$2"
    "$AD_BIN" apps --platform android --device "$device" 2>/dev/null | grep -qF "($app_id)"
}

# Parse a snapshot on stdin and emit a requested value.
#   screen -> "<width> <height>" (rendered extent)
#   edit   -> "<x> <y>" center of the lone text input (exit 1 if absent)
ad_query() {
    python3 -c '
import sys, json
mode = sys.argv[1]
d = sys.stdin.read(); s = d.find("{")
if s < 0: sys.exit(1)
obj, _ = json.JSONDecoder().raw_decode(d[s:])
nodes = obj.get("data", {}).get("nodes", [])
if mode == "screen":
    w = max((n["rect"]["x"] + n["rect"]["width"] for n in nodes), default=0)
    h = max((n["rect"]["y"] + n["rect"]["height"] for n in nodes), default=0)
    print(w, h)
elif mode == "edit":
    for n in nodes:
        if n.get("type", "").endswith("EditText"):
            r = n["rect"]; print(r["x"] + r["width"] // 2, r["y"] + r["height"] // 2); break
    else:
        sys.exit(1)
' "$1"
}

# Android + WebView versions for a device, read from adb (the WebView version is
# the current system WebView/Chromium build the app renders with). Prints
# "<android> <webview>"; either field is "unknown" if adb cannot report it.
device_versions() {
    local serial="$1" a="" w=""
    if [[ -n "$serial" ]] && command -v adb >/dev/null 2>&1; then
        a="$(adb -s "$serial" shell getprop ro.build.version.release 2>/dev/null | tr -d '\r' | tr ' ' '_')"
        w="$(adb -s "$serial" shell dumpsys webviewupdate 2>/dev/null | tr -d '\r' \
             | sed -nE 's/.*Current WebView package \(name, version\): \([^,]+, ([^)]+)\).*/\1/p' | head -1)"
    fi
    printf '%s %s\n' "${a:-unknown}" "${w:-unknown}"
}

ad_snapshot() {
    local session="$1"
    "$AD_BIN" snapshot --json --session "$session" --platform android 2>/dev/null
}

# Run the scripted interaction pass once for the current orientation.
#   $1 session   $2 screen width   $3 screen height
record_pass() {
    local session="$1" w="$2" h="$3"
    local cx=$(( w / 2 ))
    local up_from=$(( h * 72 / 100 )) up_to=$(( h * 28 / 100 ))
    local outside_y=$(( h * 18 / 100 ))

    # Scroll the whole page into view (down then back up) for the recording.
    "$AD_BIN" swipe "$cx" "$up_from" "$cx" "$up_to" --session "$session" --platform android >/dev/null 2>&1
    "$AD_BIN" swipe "$cx" "$up_from" "$cx" "$up_to" --session "$session" --platform android >/dev/null 2>&1
    sleep 1
    "$AD_BIN" swipe "$cx" "$up_to" "$cx" "$up_from" --session "$session" --platform android >/dev/null 2>&1
    "$AD_BIN" swipe "$cx" "$up_to" "$cx" "$up_from" --session "$session" --platform android >/dev/null 2>&1
    sleep 1

    # Scroll back down to the controls at the bottom of the page.
    "$AD_BIN" swipe "$cx" "$up_from" "$cx" "$up_to" --session "$session" --platform android >/dev/null 2>&1
    "$AD_BIN" swipe "$cx" "$up_from" "$cx" "$up_to" --session "$session" --platform android >/dev/null 2>&1
    sleep 1

    # Toggle the status bar twice (net layout returns to its starting state).
    "$AD_BIN" press 'id="toggle-statusbar"' --session "$session" --platform android >/dev/null 2>&1 || \
        echo "     warn: could not find 'Toggle Status Bar' button" >&2
    sleep 1
    "$AD_BIN" press 'id="toggle-statusbar"' --session "$session" --platform android >/dev/null 2>&1 || true
    sleep 1

    # Focus the input to raise the IME, then tap outside to dismiss it.
    local edit_xy
    if edit_xy="$(ad_snapshot "$session" | ad_query edit)"; then
        # shellcheck disable=SC2086
        "$AD_BIN" press $edit_xy --session "$session" --platform android >/dev/null 2>&1
        sleep 2
        "$AD_BIN" press "$cx" "$outside_y" --session "$session" --platform android >/dev/null 2>&1
        sleep 1
    else
        echo "     warn: input field not visible; skipping keyboard step" >&2
    fi
}

record_one() {
    local project="$1" device="$2"
    local app_id session out stamp dtag target
    app_id="$(app_id_for "$project")"
    # Device names can contain spaces; make a filesystem/session-safe token.
    dtag="${device//[^A-Za-z0-9._-]/_}"
    # adb serial / native-run target for this device; used to deploy and to read versions.
    target="$(device_target_for_name "$device" || true)"

    if [[ -z "$app_id" ]]; then
        echo "==> [$project@$device] skipped: could not read app id from config.xml" >&2
        return 0
    fi
    if ! app_installed "$device" "$app_id"; then
        echo "==> [$project@$device] '$app_id' not installed; deploying it first"
        if [[ -z "$target" ]]; then
            echo "==> [$project@$device] skipped: could not resolve a native-run target for '$device'" >&2
            return 0
        fi
        if ! deploy_project "$project" "$target"; then
            echo "==> [$project@$device] skipped: deploy failed (build it first: '$(basename "$0") build')" >&2
            return 0
        fi
        sleep 3
    fi

    session="rec_${project}_${dtag}"

    echo "==> [$project@$device] launching $app_id"
    "$AD_BIN" open "$app_id" --platform android --device "$device" --session "$session" --relaunch >/dev/null
    sleep 2

    # Name the file by the device android + webview version.
    local aver wver w h
    read -r aver wver <<<"$(device_versions "$target")"

    stamp="$(date +%Y%m%d-%H%M%S)"
    out="$SCRIPT_DIR/recordings/${project}_android${aver}_webview${wver}_${stamp}.mp4"

    echo "==> [$project@$device] recording to $out"
    "$AD_BIN" record start "$out" --scope device --quality high --session "$session" --platform android >/dev/null

    read -r w h <<<"$(ad_snapshot "$session" | ad_query screen)"
    : "${w:=1080}" "${h:=2400}"

    echo "     portrait pass"
    record_pass "$session" "$w" "$h"

    echo "     rotating 90deg anti-clockwise (landscape) and repeating"
    "$AD_BIN" rotate landscape-left --session "$session" --platform android >/dev/null
    sleep 2
    read -r w h <<<"$(ad_snapshot "$session" | ad_query screen)"
    : "${w:=2400}" "${h:=1080}"
    record_pass "$session" "$w" "$h"

    "$AD_BIN" rotate portrait --session "$session" --platform android >/dev/null
    sleep 1

    "$AD_BIN" record stop --session "$session" --platform android >/dev/null
    "$AD_BIN" close --session "$session" --platform android >/dev/null
    echo "==> [$project@$device] done: $out"
}

cmd_record() {
    require_agent_device || return 1
    mkdir -p "$SCRIPT_DIR/recordings"

    local device="${1:-}" project="${2:-}"

    local projects=("${PROJECTS[@]}")
    if [[ -n "$project" ]]; then
        if ! is_known_project "$project"; then
            echo "error: unknown project '$project'" >&2
            printf '       known projects: %s\n' "${PROJECTS[*]}" >&2
            return 1
        fi
        projects=("$project")
    fi

    local devices
    if [[ -n "$device" ]]; then
        devices="$device"
    else
        devices="$(booted_android_devices)"
    fi
    if [[ -z "$devices" ]]; then
        echo "error: no booted android device found; start an emulator or pass a device id" >&2
        echo "       see '$(basename "$0") record-targets'" >&2
        return 1
    fi

    local d p
    while IFS= read -r d; do
        [[ -z "$d" ]] && continue
        for p in "${projects[@]}"; do
            record_one "$p" "$d"
        done
    done <<<"$devices"
}

main() {
    local command="${1:-}"
    shift || true
    case "$command" in
        platforms) cmd_platforms ;;
        build) cmd_build ;;
        run) cmd_run "$@" ;;
        list-targets) cmd_list_targets ;;
        record) cmd_record "$@" ;;
        record-targets) cmd_record_targets ;;
        *)
            usage
            exit 1
            ;;
    esac
}

main "$@"
