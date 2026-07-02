#!/usr/bin/env bash
# Ensure a module's root Directory.Build.props imports the owned common build props
# (e.g. nuget-audit.props). Shared by deploy-module-build-props.yml and
# create-module-repository.yml so the managed-block markers stay identical.
# Copies each owned props file into the target root and injects/refreshes a
# marker-delimited <Import> block; content outside the markers is untouched.
#
# Usage: ensure-build-props-import.sh <target_dir> <props_src_dir> <props_list>
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "::error::usage: $0 <target_dir> <props_src_dir> <props_list>"
  exit 2
fi

TARGET_DIR="${1%/}"
PROPS_SRC_DIR="${2%/}"
PROPS_LIST="$3"

BEGIN='<!-- BEGIN managed: VirtoCommerce common build props -->'
END='<!-- END managed: VirtoCommerce common build props -->'
DBP="${TARGET_DIR}/Directory.Build.props"

# A module is expected to own a root Directory.Build.props — fail loudly, don't fabricate.
if [ ! -f "${DBP}" ]; then
  echo "::error::${DBP} not found — expected the module to own a root Directory.Build.props. Not creating one."
  exit 1
fi

# Copy each owned props file to the target root and build its <Import> line.
imports=''
for f in ${PROPS_LIST}; do
  cp "${PROPS_SRC_DIR}/${f}" "${TARGET_DIR}/${f}"
  imports="${imports}  <Import Project=\"\$(MSBuildThisFileDirectory)${f}\" Condition=\"Exists('\$(MSBuildThisFileDirectory)${f}')\" />"$'\n'
done

block="  ${BEGIN}"$'\n'"${imports}  ${END}"

# awk values are passed via env and read with ENVIRON[] (not -v, which interprets
# backslash escapes); ENVIRON is literal for any content.
if grep -qF "${BEGIN}" "${DBP}"; then
  # Refresh: replace everything between the markers. Guard first — a missing or
  # misplaced END would make the awk skip to EOF and drop </Project>. Test marker
  # presence with grep -q inside `if` (set -e safe); computing line numbers via a
  # failing $() would trip set -e and abort before the diagnostic could print.
  if ! grep -qF "${END}" "${DBP}"; then
    echo "::error::${DBP}: managed block is malformed (BEGIN without a matching END). Refusing to rewrite — fix the markers manually."
    exit 1
  fi
  begin_ln=$(grep -nF "${BEGIN}" "${DBP}" | head -1 | cut -d: -f1)
  end_ln=$(grep -nF "${END}" "${DBP}" | head -1 | cut -d: -f1)
  if [ "${end_ln}" -le "${begin_ln}" ]; then
    echo "::error::${DBP}: managed block is malformed (END appears before BEGIN). Refusing to rewrite — fix the markers manually."
    exit 1
  fi
  BLOCK="${block}" BEGIN_MARK="${BEGIN}" END_MARK="${END}" awk '
    index($0, ENVIRON["BEGIN_MARK"]) { print ENVIRON["BLOCK"]; skip=1; next }
    skip && index($0, ENVIRON["END_MARK"]) { skip=0; next }
    skip { next }
    { print }
  ' "${DBP}" > "${DBP}.tmp" && mv "${DBP}.tmp" "${DBP}"
  echo "Refreshed managed import block in ${DBP}."
else
  # Inject before the final </Project>.
  BLOCK="${block}" awk '
    /<\/Project>/ && !done { print ENVIRON["BLOCK"]; done=1 }
    { print }
  ' "${DBP}" > "${DBP}.tmp"
  # No </Project> (missing or self-closing) means nothing was added — verify the block
  # landed rather than deploy a props file with no import (which leaves audit off).
  if ! grep -qF "${BEGIN}" "${DBP}.tmp"; then
    rm -f "${DBP}.tmp"
    echo "::error::${DBP}: could not inject the managed import block (no </Project> to anchor it). Refusing to proceed — fix the file."
    exit 1
  fi
  mv "${DBP}.tmp" "${DBP}"
  echo "Injected managed import block into existing ${DBP}."
fi

# Warn if the module defines its own NuGet audit settings outside the managed block
# (the import line is lowercase, so it never matches <NuGetAudit). Property values are
# overridden by the import, but <NuGetAuditSuppress> items are additive — a stale local
# suppress can outlive a central change, so surface it for cleanup.
inline_audit=$(grep -nE '<NuGetAudit' "${DBP}" || true)
if [ -n "${inline_audit}" ]; then
  module=$(basename "${TARGET_DIR}")
  echo "::warning::${module}: Directory.Build.props defines its own NuGet audit settings; these are centrally managed via ${PROPS_LIST}. Property values are overridden by the import; NuGetAuditSuppress items are additive — remove the inline settings to keep one source of truth."
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
      echo "### ⚠️ ${module}: inline NuGet audit settings found"
      echo ""
      echo "\`Directory.Build.props\` defines NuGet audit settings outside the managed block, now centrally managed by the imported \`${PROPS_LIST}\`:"
      echo "- Property values (\`NuGetAudit\` / \`NuGetAuditMode\` / \`NuGetAuditLevel\`) are **overridden** by the import (evaluated last)."
      echo "- \`NuGetAuditSuppress\` items are **additive** — a stale local entry can outlive a central change. Remove them to keep a single source of truth."
      echo ""
      echo "Found:"
      echo '```'
      printf '%s\n' "${inline_audit}"
      echo '```'
    } >> "${GITHUB_STEP_SUMMARY}"
  fi
fi
