#!/usr/bin/env bash
# Ensure a module's root Directory.Build.props IMPORTS the fully-owned common
# build props (e.g. nuget-audit.props). Shared by:
#   - deploy-module-build-props.yml   (distribute to existing modules)
#   - create-module-repository.yml    (scaffold at module creation)
#
# Keeping this in one place means the managed-block markers are identical across
# both call sites, so the in-place "refresh" path always matches what was written.
#
# Behaviour: copy each owned props file into the target repo root (overwrite =
# safe, we own them) and inject/refresh a marker-delimited managed block that
# imports them. Everything outside the markers is left untouched. A module with
# no Directory.Build.props is an anomaly — fail loudly rather than fabricate one.
#
# Usage: ensure-build-props-import.sh <target_dir> <props_src_dir> <props_list>
#   target_dir     module repo working copy (must contain Directory.Build.props)
#   props_src_dir  dir holding the owned *.props files (…/common-build-props)
#   props_list     space-separated props filenames to copy and import
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

if [ ! -f "${DBP}" ]; then
  echo "::error::${DBP} not found — expected the module to own a root Directory.Build.props. Not creating one."
  exit 1
fi

# Copy each owned props file to the target root and build the <Import> lines.
imports=''
for f in ${PROPS_LIST}; do
  cp "${PROPS_SRC_DIR}/${f}" "${TARGET_DIR}/${f}"
  imports="${imports}  <Import Project=\"\$(MSBuildThisFileDirectory)${f}\" Condition=\"Exists('\$(MSBuildThisFileDirectory)${f}')\" />"$'\n'
done

block="  ${BEGIN}"$'\n'"${imports}  ${END}"

# Values are passed to awk via the environment and read with ENVIRON[] rather than
# `-v`, because `-v` interprets backslash escape sequences in the value; ENVIRON is
# literal for any content. (Shell quoting is unaffected either way.)
if grep -qF "${BEGIN}" "${DBP}"; then
  # Managed block already present — replace everything between the markers.
  BLOCK="${block}" BEGIN_MARK="${BEGIN}" END_MARK="${END}" awk '
    index($0, ENVIRON["BEGIN_MARK"]) { print ENVIRON["BLOCK"]; skip=1; next }
    skip && index($0, ENVIRON["END_MARK"]) { skip=0; next }
    skip { next }
    { print }
  ' "${DBP}" > "${DBP}.tmp" && mv "${DBP}.tmp" "${DBP}"
  echo "Refreshed managed import block in ${DBP}."
else
  # No managed block yet — inject it just before the final </Project>.
  BLOCK="${block}" awk '
    /<\/Project>/ && !done { print ENVIRON["BLOCK"]; done=1 }
    { print }
  ' "${DBP}" > "${DBP}.tmp" && mv "${DBP}.tmp" "${DBP}"
  echo "Injected managed import block into existing ${DBP}."
fi

# Surface any NuGet audit settings the module defines on its OWN (element tags
# outside the managed block — the import line uses the lowercase file name, so it
# never matches). The imported props override property VALUES (evaluated last),
# but <NuGetAuditSuppress> items are additive: a stale local suppress can silently
# outlive a central change. Report to the workflow run summary when available, and
# always as a warning annotation / log line.
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
