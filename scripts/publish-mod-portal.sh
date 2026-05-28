#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOD_NAME="$(python3 -c 'import json; print(json.load(open("info.json"))["name"])' < /dev/null)"
VERSION="$(python3 -c 'import json; print(json.load(open("info.json"))["version"])' < /dev/null)"
TITLE="${TITLE:-$(python3 -c 'import json; print(json.load(open("info.json")).get("title", ""))' < /dev/null)}"
INFO_DESCRIPTION="$(python3 -c 'import json; print(json.load(open("info.json")).get("description", ""))' < /dev/null)"
SUMMARY="${PORTAL_SUMMARY:-$INFO_DESCRIPTION}"
ZIP_PATH="${ZIP_PATH:-"$ROOT/../${MOD_NAME}_${VERSION}.zip"}"
TOKEN="${FACTORIO_MOD_PORTAL_TOKEN:-${MOD_UPLOAD_API_KEY:-${FACTORIO_TOKEN:-}}}"
MOD_PORTAL_URL="${MOD_PORTAL_URL:-https://mods.factorio.com}"
DESCRIPTION_FILE="${DESCRIPTION_FILE:-"$ROOT/README.md"}"
CATEGORY="${CATEGORY:-scenarios}"
LICENSE="${LICENSE:-default_gnugplv3}"
SOURCE_URL="${SOURCE_URL:-https://github.com/zzh8829/mts-expanse}"

if [[ -z "$TOKEN" ]]; then
    echo "Set FACTORIO_MOD_PORTAL_TOKEN or FACTORIO_TOKEN to a Factorio API key with ModPortal: Publish Mods and ModPortal: Edit Mods." >&2
    echo "Create it at https://factorio.com/profile" >&2
    exit 2
fi

if [[ ! -f "$ZIP_PATH" ]]; then
    echo "Missing mod zip: $ZIP_PATH" >&2
    echo "Run scripts/test.sh first to build it." >&2
    exit 2
fi

if unzip -Z1 "$ZIP_PATH" | grep -Eiq '\\.(exe|bat|ps1|sh|py)$'; then
    echo "Mod Portal rejects executable/helper files in release zips." >&2
    echo "Run scripts/test.sh to rebuild a sanitized package without scripts/." >&2
    exit 2
fi

tmp_init="$(mktemp)"
tmp_upload="$(mktemp)"
cleanup() {
    rm -f "$tmp_init" "$tmp_upload"
}
trap cleanup EXIT

echo "Publishing $MOD_NAME $VERSION from $ZIP_PATH"

init_upload() {
    local endpoint="$1"
    curl -sS \
        -H "Authorization: Bearer $TOKEN" \
        -F "mod=$MOD_NAME" \
        "$endpoint" \
        -o "$tmp_init"
}

init_upload "$MOD_PORTAL_URL/api/v2/mods/init_publish"
upload_mode=publish
init_result="$(python3 - "$tmp_init" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
upload_url = data.get("upload_url")
if upload_url:
    print("upload " + upload_url)
elif data.get("error") == "ModAlreadyExists":
    print("exists")
else:
    raise SystemExit(json.dumps(data))
PY
)"

if [[ "$init_result" == "exists" ]]; then
    init_upload "$MOD_PORTAL_URL/api/v2/mods/releases/init_upload"
    upload_mode=release
    init_result="$(python3 - "$tmp_init" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
upload_url = data.get("upload_url")
if not upload_url:
    raise SystemExit(json.dumps(data))
print("upload " + upload_url)
PY
)"
fi

upload_url="${init_result#upload }"

upload_args=(
    -fsS
    -F "file=@$ZIP_PATH"
)

if [[ "$upload_mode" == "publish" ]]; then
    upload_args+=(-F "category=$CATEGORY" -F "license=$LICENSE")

    if [[ -f "$DESCRIPTION_FILE" ]]; then
        upload_args+=(-F "description=<$DESCRIPTION_FILE")
    fi

    if [[ -n "$SOURCE_URL" ]]; then
        upload_args+=(-F "source_url=$SOURCE_URL")
    fi
fi

curl "${upload_args[@]}" "$upload_url" -o "$tmp_upload"

python3 - "$tmp_upload" "$MOD_PORTAL_URL" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
if not data.get("success"):
    raise SystemExit(json.dumps(data))
url = data.get("url")
if url:
    print(f"Published: {sys.argv[2].rstrip('/')}{url}")
else:
    print("Published release")
PY

edit_args=(
    -fsS
    -H "Authorization: Bearer $TOKEN"
    -F "mod=$MOD_NAME"
    -F "category=$CATEGORY"
    -F "license=$LICENSE"
)

if [[ -n "$TITLE" ]]; then
    edit_args+=(-F "title=$TITLE")
fi

if [[ -n "$SUMMARY" ]]; then
    edit_args+=(-F "summary=$SUMMARY")
fi

if [[ -f "$DESCRIPTION_FILE" ]]; then
    edit_args+=(-F "description=<$DESCRIPTION_FILE")
fi

if [[ -n "$SOURCE_URL" ]]; then
    edit_args+=(-F "source_url=$SOURCE_URL")
fi

curl "${edit_args[@]}" "$MOD_PORTAL_URL/api/v2/mods/edit_details" -o "$tmp_upload"

python3 - "$tmp_upload" "$MOD_PORTAL_URL" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
if not data.get("success"):
    raise SystemExit(json.dumps(data))
url = data.get("url")
if url:
    print(f"Updated details: {sys.argv[2].rstrip('/')}{url}")
else:
    print("Updated details")
PY
