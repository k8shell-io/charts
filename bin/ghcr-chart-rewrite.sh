#!/bin/bash
# ghcr-chart-rewrite.sh CHART_DIR — turn a released k8shell chart into its public ghcr.io form.
#
# Rewrites CHART_DIR/values.yaml in place: every image repository
# registry.k8shell.io/<project>/<name> becomes ghcr.io/k8shell-io/<name>, and
# imageRegistry.host is emptied (public images need no pull Secret). Writes the
# image pairs "<internal ref> <ghcr.io ref>" to images.txt next to CHART_DIR, for
# the digest check before publishing. Fails when a reference to the internal
# registry is left outside comments, or an image is not a release tag.
#
# Used by .github/workflows/promote-k8shell.yaml; safe to run locally on a pulled
# chart (helm pull ... --untar).
set -euo pipefail

chart="${1:?usage: $0 CHART_DIR}"
values="$chart/values.yaml"
images="$(dirname "$chart")/images.txt"
[ -f "$values" ] || { echo "no $values" >&2; exit 1; }

# pairs from the original values: a repository line and the next tag line
awk '
  /^[[:space:]]*repository:[[:space:]]*registry\.k8shell\.io\// { repo = $2; next }
  repo != "" && /^[[:space:]]*tag:/ {
    tag = $2; gsub(/"/, "", tag)
    name = repo; sub(/.*\//, "", name)
    print repo ":" tag, "ghcr.io/k8shell-io/" name ":" tag
    repo = ""
  }
' "$values" > "$images"

bad=$(awk '{ split($1, a, ":"); t = a[length(a)] } t !~ /^v[0-9]+\.[0-9]+\.[0-9]+$/ { print $1 }' "$images")
if [ -n "$bad" ]; then
    echo "not release tags:" >&2
    echo "$bad" >&2
    exit 1
fi

sed -i -E \
    -e 's#^([[:space:]]*repository:[[:space:]]*)registry\.k8shell\.io/[^/[:space:]]+/#\1ghcr.io/k8shell-io/#' \
    -e '/^imageRegistry:/,/^[^[:space:]#]/ s#^(  host:[[:space:]]*)registry\.k8shell\.io[[:space:]]*$#\1""#' \
    "$values"

left=$(grep -nE 'registry\.k8shell\.io' "$values" | grep -vE '^[0-9]+:[[:space:]]*#' || true)
if [ -n "$left" ]; then
    echo "internal registry left in $values:" >&2
    echo "$left" >&2
    exit 1
fi
echo "$(wc -l < "$images") images rewritten to ghcr.io/k8shell-io; imageRegistry.host emptied"
