#!/bin/bash
# Download Phonon 31M (gradium/phonon-31m-en, Apache-2.0) as Core ML into Models/, the folder the
# app bundles. Weights are not committed to this repository.
#
#   scripts/fetch-model.sh
#
# The bundle is the one the xn-ptts release ships, exported from the Hugging Face repo with the
# English voices of gradium/phonon-voices (its source.json names both). Keep VERSION in step with
# the PhononTTS package version in project.yml. The 12 character voices are taken out: they don't
# suit a coach, so Settings lists the 25 regular American and British voices.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=0.4.0
URL=https://github.com/gradium-ai/xn-ptts/releases/download/v$VERSION/phonon-31m-en-coreml.zip
SHA256=10f3a99fd39256db44f826267ef21d78cca959b16c0554926344c09fde27b436
ZIP=build/phonon-31m-en-coreml-$VERSION.zip

if ! [ -s "$ZIP" ] || ! echo "$SHA256  $ZIP" | shasum -a 256 -c --status; then
  echo "downloading $URL"
  mkdir -p build
  curl -fL --retry 3 -o "$ZIP.part" "$URL"
  echo "$SHA256  $ZIP.part" | shasum -a 256 -c --status || { echo "$URL: checksum mismatch" >&2; exit 1; }
  mv "$ZIP.part" "$ZIP"
fi

OUT=build/phonon-coreml
rm -rf "$OUT"
mkdir -p "$OUT"
unzip -q "$ZIP" -d "$OUT"
BUNDLE="$OUT/phonon-31m-en-coreml"

# The character voices, by the catalog's locale, at the revision the bundle was exported from.
CATALOG=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["voices"])' "$BUNDLE/source.json")
CATALOG=${CATALOG#hf://}
curl -fsSL --retry 3 -o "$OUT/voices.jsonl" "https://huggingface.co/${CATALOG%@*}/resolve/${CATALOG#*@}/voices.jsonl"
python3 - "$BUNDLE" "$OUT/voices.jsonl" <<'PY'
import json, pathlib, sys
bundle, catalog = pathlib.Path(sys.argv[1]), sys.argv[2]
characters = {v["name"] for v in map(json.loads, open(catalog)) if v["locale"] == "characters"}
manifest = json.loads((bundle / "bundle.json").read_text())
assert characters <= set(manifest["voices"]), "the bundle's voices are not the catalog's"
for name in characters:
    (bundle / "voices" / f"{name}.safetensors").unlink()
manifest["voices"] = [v for v in manifest["voices"] if v not in characters]
manifest["files"] = [f for f in manifest["files"] if f["path"].removeprefix("voices/").removesuffix(".safetensors") not in characters]
(bundle / "bundle.json").write_text(json.dumps(manifest, indent=2) + "\n")
PY

# Swap it in, keeping Models/README.md.
find Models -mindepth 1 ! -name README.md -exec rm -rf {} +
cp -R "$BUNDLE"/. Models/
# The Desktop may be iCloud-synced, and Finder metadata on the .mlpackage folders breaks
# code signing ("resource fork, Finder information, or similar detritus not allowed").
xattr -cr Models
echo "Models/: $(du -sh Models | cut -f1), voices: $(ls Models/voices | sed 's/\.safetensors//' | tr '\n' ' ')"
