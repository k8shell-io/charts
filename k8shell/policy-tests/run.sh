#!/usr/bin/env bash
# Runs the Rego policy tests against the chart's default policies
# (files/policies). enrich.user is a custom builtin provided by the authz
# service, so it is declared in a generated capabilities file and mocked in the
# tests with `with enrich.user as ...`.
# Needs opa and jq; set OPA to the opa binary if it isn't on PATH.
# Extra arguments go to opa test (e.g. -v).
set -euo pipefail

OPA="${OPA:-opa}"
here="$(cd "$(dirname "$0")" && pwd)"
chart="$(dirname "$here")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

"$OPA" capabilities --current \
  | jq '.builtins += [{"name": "enrich.user", "decl": {"type": "function", "args": [{"type": "string"}], "result": {"type": "any"}}}]' \
  > "$tmp/capabilities.json"

"$OPA" test --capabilities "$tmp/capabilities.json" "$chart/files/policies" "$here" "$@"
