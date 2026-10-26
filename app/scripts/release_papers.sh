#!/bin/zsh
# Uploads the past-paper PDFs as their own GitHub release (tag from Resources/bank/<subject>/pack.json),
# if that exact pack isn't published yet. Apps download it once on first launch.
set -euo pipefail
cd "$(dirname "$0")/.."
for manifest in Resources/bank/*/pack.json; do
  dir=$(dirname "$manifest")
  tag=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['tag'])" "$manifest")
  asset=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['asset'])" "$manifest")
  if gh release view "$tag" >/dev/null 2>&1; then
    echo "Paper pack $tag already published."
    continue
  fi
  [[ -d "$dir/papers" ]] || { echo "No papers in $dir — run pipeline/build_bank.py first." >&2; exit 1; }
  tmp=$(mktemp -d)
  (cd "$dir" && ditto -c -k --keepParent papers "$tmp/$asset")
  gh release create "$tag" "$tmp/$asset" --title "Past papers: $(basename "$dir") ($tag)" \
    --notes "Past-paper PDFs downloaded by Biosphere on first launch. Not an app release." --prerelease --latest=false
  echo "Published paper pack $tag ($(du -sh "$tmp/$asset" | cut -f1))."
done
