#!/usr/bin/env bash

set -euo pipefail

readonly EXPECTED_BUNDLE_ID="com.lyonzzzzzzzz.SkyTrace.mac"
readonly DEFAULT_OUTPUT_ROOT="${HOME}/Applications/SkyTrace"

usage() {
    cat <<'USAGE'
Usage:
  Scripts/publish_local_macos_app.sh <source.app> [--output-root DIR] [--replace]

Copies a macOS SkyTrace App into a versioned local Applications directory,
changes only its Finder display name, and re-signs the copy ad-hoc.

Options:
  --output-root DIR  Destination directory (default: ~/Applications/SkyTrace)
  --replace          Replace an existing versioned App at the destination
  -h, --help         Show this help
USAGE
}

fail() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

source_app="${1:-}"
if [[ -z "${source_app}" ]]; then
    usage
    exit 2
fi
shift

output_root="${DEFAULT_OUTPUT_ROOT}"
replace_existing=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output-root)
            [[ $# -ge 2 ]] || fail "--output-root requires a directory"
            output_root="$2"
            shift 2
            ;;
        --replace)
            replace_existing=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "unknown option: $1"
            ;;
    esac
done

[[ -d "${source_app}" ]] || fail "source App does not exist: ${source_app}"
[[ "${source_app}" == *.app ]] || fail "source path must end with .app"

info_plist="${source_app}/Contents/Info.plist"
[[ -f "${info_plist}" ]] || fail "missing Info.plist: ${info_plist}"

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${info_plist}" 2>/dev/null || true)"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${info_plist}" 2>/dev/null || true)"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${info_plist}" 2>/dev/null || true)"

[[ "${bundle_id}" == "${EXPECTED_BUNDLE_ID}" ]] || \
    fail "unexpected Bundle ID '${bundle_id}', expected '${EXPECTED_BUNDLE_ID}'"
[[ "${version}" =~ ^[0-9]+([.][0-9]+){1,2}$ ]] || fail "invalid marketing version: '${version}'"
[[ "${build_number}" =~ ^[0-9]+$ ]] || fail "invalid build number: '${build_number}'"

destination_app="${output_root}/SkyTrace-${version}.app"
if [[ -e "${destination_app}" ]]; then
    [[ "${replace_existing}" -eq 1 ]] || \
        fail "destination already exists: ${destination_app} (use --replace to overwrite)"
    rm -rf "${destination_app}"
fi

mkdir -p "${output_root}"
/usr/bin/ditto "${source_app}" "${destination_app}"

destination_plist="${destination_app}/Contents/Info.plist"
display_name="星迹 ${version}"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName ${display_name}" "${destination_plist}" >/dev/null

/usr/bin/codesign --force --deep --sign - "${destination_app}" >/dev/null
/usr/bin/codesign --verify --deep --strict "${destination_app}"

printf 'Published %s (%s)\n' "${destination_app}" "${display_name}"
printf 'Bundle ID: %s\n' "${bundle_id}"
printf 'Version: %s (build %s)\n' "${version}" "${build_number}"
