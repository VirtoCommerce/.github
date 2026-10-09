#!/usr/bin/env bash
# Self-check for reviewers.jq: bash reviewers.test.sh
set -euo pipefail
here="$(dirname "$0")"

pr='{"user": {"login": "author"}, "requested_reviewers": [{"login": "maya"}, {"login": "andrew"}]}'
reviews='[
  {"user": {"login": "maya"},   "state": "CHANGES_REQUESTED", "submitted_at": "2026-10-01T10:00:00Z"},
  {"user": {"login": "ivan"},   "state": "APPROVED",          "submitted_at": "2026-10-01T11:00:00Z"},
  {"user": {"login": "ivan"},   "state": "COMMENTED",         "submitted_at": "2026-10-01T12:00:00Z"},
  {"user": {"login": "olga"},   "state": "COMMENTED",         "submitted_at": "2026-10-01T12:00:00Z"},
  {"user": {"login": "petr"},   "state": "APPROVED",          "submitted_at": "2026-10-01T09:00:00Z"},
  {"user": {"login": "petr"},   "state": "DISMISSED",         "submitted_at": "2026-10-01T13:00:00Z"},
  {"user": {"login": "author"}, "state": "COMMENTED",         "submitted_at": "2026-10-01T14:00:00Z"}
]'
got=$(jq -nc --argjson pr "$pr" --argjson reviews "$reviews" -f "$here/reviewers.jq" | jq -c 'map({(.login): .state}) | add')
want='{"andrew":"waiting","ivan":"approved","maya":"rereview","olga":"comments","petr":"waiting"}'
[ "$got" = "$want" ] || { echo "FAIL review states: $got"; exit 1; }

echo OK
