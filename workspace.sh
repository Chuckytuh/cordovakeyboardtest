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

Examples:
  $(basename "$0") platforms
  $(basename "$0") build
  $(basename "$0") run Pixel_7_API_34
  $(basename "$0") run emulator-5554 cordova-android15_e2e
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
        local apk
        apk="$(find_apk "$p")"
        echo "==> [$p] deploying $apk to target '$target'"
        npx native-run android --app "$apk" --target "$target"
    done
}

cmd_list_targets() {
    npx native-run android --list
}

main() {
    local command="${1:-}"
    shift || true
    case "$command" in
        platforms) cmd_platforms ;;
        build) cmd_build ;;
        run) cmd_run "$@" ;;
        list-targets) cmd_list_targets ;;
        *)
            usage
            exit 1
            ;;
    esac
}

main "$@"
