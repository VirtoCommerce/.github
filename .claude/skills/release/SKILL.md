---
name: release
description: >
  Cut a release of this repo's reusable workflows, templates and actions: pin every
  internal VirtoCommerce/.github ref to the new vX.Y.Z tag, bump the version headers, the
  deploy default and the docs, tag the merge commit, and deploy to the module repos.
  Use when the user says "release", "cut a release", "pin to v3.x", "tag the release",
  or invokes /release with an optional version.
---

Release this repo. `$ARGUMENTS` is the new version (`v3.1000.2`) and optionally the Jira ticket. If the version is missing, propose the next patch of the newest tag (`git tag --sort=-v:refname | head -1`) and confirm it. The ticket defaults to the one in the branch name (`vcst-6033-...` → `VCST-6033`).

Never commit, push or tag without the user's explicit OK for that step: stage, show the diff summary, ask.

## 1. Pin the release in the feature PR (one commit)

On the PR branch, before merge. Commit message: `<TICKET>: Pin actions and workflows to <new>`.

In `.github/workflows/` and `workflow-templates/`:

- Every `uses: VirtoCommerce/.github/...@<ref>` where `<ref>` is the previous tag or a temporary branch ref (`@vcst-6033-playwright-workflow`, `@VCST-5414`) → `@<new>`.
- The version header on line 1 (`# v3.1000.1`) → `# <new>`, and the ticket header on line 2 (`# https://virtocommerce.atlassian.net/browse/<TICKET>`) → this release's ticket. Only in files that have the headers.
- `deploy-module-workflows.yml`: the `default:` of the version input → `'<new>'`.

The docs, in the same commit:

- `actions/*/README.md`: the `uses: VirtoCommerce/.github/actions/<x>@<previous>` example → `@<new>`.
- `actions/README.md`: the generic `@<previous>` line.
- `deprecated/workflows/*.yml`: the `# <previous>` header.

Leave these alone — they are not release refs:

- `PINACT_VERSION` in `auto-update-templates.yml` / `pin-check.yml` (a tool version).
- `deprecated-residual-callers.md` (a snapshot of what callers used).
- The `git tag ... v3.800.0` example in the root `README.md`.
- Anything under `node_modules/`.

Verify before committing:

- `git grep -nE 'uses: *VirtoCommerce/\.github/[^@ ]+@' -- .github/workflows workflow-templates actions ':!**/node_modules/**' | grep -v '@<new>'` prints nothing. Anchored on `uses:`, so prose like `actions/<action>@<tag>` in `actions/README.md` doesn't match.
- `git grep -n '<previous tag>' -- .github/workflows workflow-templates actions deprecated ':!**/node_modules/**'` prints nothing.

## 2. Tag the merge commit

After the PR is merged, and only with the user's OK:

```bash
git fetch origin
git ls-remote --tags origin <new>        # must be empty
git tag -a -m "<one-line summary> (<TICKET>)" <new> <merge commit sha>
git push origin <new>                    # the tag only
```

The tag is annotated (as `v3.1000.1` is), on the PR's merge commit on `main`. Until it exists, every `@<new>` ref fails with "unable to resolve action", so push it right after the merge.

## 3. Deploy

Per the root README's "Update workflow templates":

- Run `Deploy Module workflows` (and `Deploy Platform workflows` if platform templates changed) with `Version to deploy` = `<new>`. It has `repos` and `dryRun` inputs: offer a dry run, or 2–3 sample repos, before the full list.
- Update the composable workflow versions in vc-modules, vc-platform, vc-frontend and vc-testing-module.

## Report

What was pinned (file count), the tag and its commit, which deploy ran and its run link, and anything skipped.
