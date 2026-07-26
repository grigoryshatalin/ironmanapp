#!/bin/bash
# Regenerates docs/screenshots/ from the ScreenshotTests UI suite.
# Screenshots are XCTAttachments, so they are extracted from the .xcresult bundle.
set -euo pipefail
cd "$(dirname "$0")/.."

RESULT="${TMPDIR:-/tmp}/endurance-screenshots.xcresult"
rm -rf "$RESULT"

xcodebuild test \
  -project Endurance.xcodeproj -scheme Endurance \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:EnduranceUITests/ScreenshotTests \
  -resultBundlePath "$RESULT" \
  CODE_SIGNING_ALLOWED=NO

mkdir -p docs/screenshots
STAGE="${TMPDIR:-/tmp}/endurance-shots-stage"
rm -rf "$STAGE"; mkdir -p "$STAGE"
xcrun xcresulttool export attachments --path "$RESULT" --output-path "$STAGE"

# The export writes a manifest mapping suggested names to files on disk.
python3 - "$STAGE" <<'PY'
import json, pathlib, re, shutil, sys
stage = pathlib.Path(sys.argv[1])
out = pathlib.Path("docs/screenshots")
manifest = json.loads((stage / "manifest.json").read_text())
count = 0
for entry in manifest:
    for att in entry.get("attachments", []):
        name = att.get("suggestedHumanReadableName") or att.get("exportedFileName")
        src = stage / att["exportedFileName"]
        if not src.exists():
            continue
        # Exporter appends "_<n>_<UUID>"; keep just our own name.
        stem = re.sub(r"_\d+_[0-9A-Fa-f-]{36}$", "", pathlib.Path(name).stem)
        shutil.copyfile(src, out / f"{stem}.png")
        count += 1
print(f"exported {count} screenshots -> {out}")
PY
