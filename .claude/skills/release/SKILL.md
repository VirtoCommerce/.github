---
name: release
description: >
  Cut a release of this repo's reusable workflows, templates and actions: pin every
  internal VirtoCommerce/.github ref in the workflows and templates to the new vX.Y.Z tag,
  bump the version headers and the deploy default, tag the merge commit, and deploy to
  the module repos. Or roll out a new vc-build version: bump VCBUILD_VERSION in
  setup-vcbuild and move the floating `stable` tag, with no release of this repo.
  Use when the user says "release", "cut a release", "pin to v3.x", "tag the release",
  "release vc-build X", "move stable", or invokes /release with an optional version.
---

Release this repo. `$ARGUMENTS` is one of:

- the new version (`v3.1000.2`) and optionally the Jira ticket → a release of this repo, sections 1–3. If the version is missing, propose the next patch of the newest tag (`git tag --sort=-v:refname | head -1`) and confirm it.
- `vc-build <version>` (`vc-build 3.1002.1`) and optionally the ticket → a new vc-build, section 4 only.

The ticket defaults to the one in the branch name (`vcst-6033-...` → `VCST-6033`).

Never commit, push or tag without the user's explicit OK for that step: stage, show the diff summary, ask.

Two kinds of tags:

- `vX.Y.Z`: a release. Every internal ref in the workflows and templates names it, and the module repos get it by the deploy (section 3).
- `stable`: floating, for `actions/setup-vcbuild` only. Every workflow and template, and the vc-deploy-dev branches, call `setup-vcbuild@stable`, so moving it rolls out a vc-build version (or any other change of setup-vcbuild) everywhere at once, without a release. A release never pins it and never moves it.

## 1. Pin the release (one commit)

Every release pins, even one that changes no workflow or template (e.g. a new action only): the refs, headers and deploy default always name the tag they are released in.

Where: on the feature PR branch, before merge, when the PR changes workflows or templates. Otherwise (the feature PR is already merged, or it touches only actions or docs) in a separate PR from `origin/main` (`--no-track`), and the tag goes on that PR's merge commit. Commit message: `<TICKET>: Pin actions and workflows to <new>`.

In `.github/workflows/` and `workflow-templates/`:

- Every `uses: VirtoCommerce/.github/...@<ref>` where `<ref>` is any older tag or a temporary branch ref (`@vcst-6033-playwright-workflow`, `@VCST-5414`) → `@<new>`. Except `setup-vcbuild@stable`: leave it.
- The version header on line 1 (`# v3.1000.1`) → `# <new>`, and the ticket header on line 2 (`# https://virtocommerce.atlassian.net/browse/<TICKET>`) → this release's ticket. Only in files that have the headers.
- `deploy-module-workflows.yml`: the `default:` of the version input → `'<new>'`.

Leave these alone — they are not release refs:

- `setup-vcbuild@stable`, everywhere.
- The docs inside `actions/`: the `@<previous>` examples in `actions/*/README.md` and `actions/README.md`. A README of an action that is new in this release still shows `@<new>`, since the previous tag doesn't have that action.
- Everything under `deprecated/`, version headers included.
- Tool versions: `ZIZMOR_VERSION` in `auto-update-templates.yml`, `ZIZMOR_VERSION` and `ACTIONLINT_VERSION` in `workflow-security.yml`, `PINACT_VERSION` in `pin-check.yml`.
- `deprecated-residual-callers.md` (a snapshot of what callers used).
- The `git tag ... v3.800.0` example in the root `README.md`.

Verify before committing:

- `git grep -nE 'uses: *VirtoCommerce/\.github/[^@ ]+@' -- .github/workflows workflow-templates | grep -v -e '@<new>' -e 'setup-vcbuild@stable$'` prints nothing. Any other action `@stable` is a mistake: only setup-vcbuild floats.
- `git grep -nE '^# v3\.' -- .github/workflows workflow-templates | grep -v '# <new>'` prints nothing (version headers).
- `git diff --stat` counts only the changed lines (about 68 refs + 17 + 17 headers + 1 default). Edit with a tool that keeps CRLF line ends: Git Bash `sed -i` rewrites them and turns the diff into whole files.

If the release changes `actions/setup-vcbuild`, that change reaches nobody through the new tag: after the merge, move `stable` as in section 4 (the bump step is then already done).

## 2. Tag the merge commit

After the PR is merged, and only with the user's OK:

```bash
git fetch origin
git ls-remote --tags origin <new>        # must be empty
gh pr view <PR> --json mergeCommit --jq .mergeCommit.oid
# the merge commit carries only @<new> refs (no temporary branch refs left):
git grep -nE 'uses: *VirtoCommerce/\.github/[^@ ]+@' <merge commit sha> -- .github/workflows workflow-templates | grep -v -e '@<new>' -e 'setup-vcbuild@stable$'   # must be empty
git tag -a -m "<one-line summary> (<TICKET>)" <new> <merge commit sha>
git push origin <new>                    # the tag only
```

The tag is annotated (as `v3.1000.1` is), on the PR's merge commit on `main`. Until it exists, every `@<new>` ref fails with "unable to resolve action", so push it right after the merge.

## 3. Deploy

Ask whether to deploy now when the templates changed only by the pin: the module repos keep working on the older tag. Per the root README's "Update workflow templates":

- Run `Deploy Module workflows` (and `Deploy Platform workflows` if platform templates changed) with `Version to deploy` = `<new>`. It has `repos` and `dryRun` inputs: offer a dry run, or 2–3 sample repos, before the full list.
- Update the composable workflow versions in vc-modules, vc-platform, vc-frontend and vc-test-automation-framework: a PR to each default branch with every `VirtoCommerce/.github/...@<ref>` → `@<new>`, except `setup-vcbuild`, which goes to `@stable` (from any tag, so the repo follows the vc-build rollouts from then on). Search all their workflow files, not only the ones that call the reusable workflows: vc-platform calls setup-vcbuild directly in its CI, hotfix, NuGet, CodeQL and OWASP workflows. Report a workflow that installs vc-build with `dotnet tool install ... VirtoCommerce.GlobalTool` instead (an unpinned latest from NuGet): it should move to `setup-vcbuild@stable`, but ask first.

## 4. A new vc-build: move `stable`

No `vX.Y.Z` tag, no pin, no deploy. The module repos and the vc-deploy-dev branches pick the new version up on their next run.

1. Check that `<version>` is on NuGet and is not a prerelease: `curl -s https://api.nuget.org/v3-flatcontainer/virtocommerce.globaltool/index.json`. A prerelease is tested with `/test-workflows`, not released.
2. PR from `origin/main` (`--no-track`): `VCBUILD_VERSION` in `actions/setup-vcbuild/index.js` → `'<version>'`. Commit message: `<TICKET>: vc-build <version>`. The PR runs the `vc-build canary` workflow on the new version; it must be green before the merge.
3. After the merge, with the user's OK:

```bash
git fetch origin --tags --force
gh pr view <PR> --json mergeCommit --jq .mergeCommit.oid
git show <merge commit sha>:actions/setup-vcbuild/index.js | grep "VCBUILD_VERSION ="   # names <version>
git diff --stat stable <merge commit sha> -- actions/setup-vcbuild   # only what this rollout means to ship
git rev-parse 'stable^{}'                # note it: the rollback target
git tag -f -a -m "vc-build <version> (<TICKET>)" stable <merge commit sha>
git push -f origin refs/tags/stable      # the floating tag only
git ls-remote --tags origin 'stable^{}'  # names the merge commit
```

`stable` moves to a commit of `main`, which may carry unreleased changes of other actions. That is fine: only setup-vcbuild is referenced `@stable`. But the `git diff` above must show only the setup-vcbuild changes meant for this rollout.

4. Run `vc-build canary` on `main` by dispatch (empty `version`) to confirm the pinned version from the tagged commit.

Rollback: move `stable` back to the noted commit the same way. The message of each `stable` tag names its vc-build version.

## Report

Release: what was pinned (file count), the tag and its commit, which deploy ran and its run link, and anything skipped.

vc-build: the version, the PR and its canary run, where `stable` points now and where it pointed before, the canary run on `main`.
