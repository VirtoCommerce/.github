---
name: test-workflows
description: >
  Test a change of this repo's reusable workflows and actions, or a new vc-build version,
  on a real repository before release: a temporary branch here with the change and every
  internal ref pointed at it, a temporary branch in a chosen module (or other) repo that
  uses it, a live run there, plus A/B repros and local checks where possible.
  Use when the user says "test the new vc-build", "check alpha X on repo Y",
  "test these workflow changes on a module", or invokes /test-workflows.
---

Test a change before it is released. `$ARGUMENTS` says what to test: a vc-build version
(`3.1003.0-alpha.305`), a branch of this repo, or an action/workflow; optionally the
Jira ticket, a target repo, and a failing run or PR the change should fix. The ticket
defaults to the one in the current branch name.

Rules for the whole flow:

- Never push, dispatch, rerun or delete without the user's OK for that step. Say what
  the step will run and what it publishes, then ask.
- Only temporary branches of our own. Never push to someone's PR branch, never open a
  PR for a test branch, never merge one.
- Nothing posted to a tracker carries a local path (see the global rules).

## 1. Understand what to prove

Before touching anything, write down the scenario the test must cover: what fails on
the old version and must pass on the new one, or what must keep working.

- New vc-build: list the commits between the pinned version (`VCBUILD_VERSION` in
  `actions/setup-vcbuild/index.js`) and the new one
  (`gh api repos/VirtoCommerce/vc-build/compare/<old>...<new>`), read the diffs, and note
  which targets and code paths they touch.
- A failing run: find the failing step, the exception and the stack, and the
  *condition* under which it fails. Example: 3.1002.0 `vc-build install` threw
  `UriFormatException` in `ExtModuleCatalog.SetLocalModuleRefs` only when `./publish`
  already held a module missing from the external catalog (the module under test from a
  warm cache) — a green cold run proves nothing about that bug.
- A workflow/action change: which callers use it, with which inputs.

The scenario decides the target repo (step 3) and the repro (step 5).

## 2. The test branch in this repo

- Name: `<TICKET>-test-<slug>` (e.g. `VCST-6856-vcbuild-alpha305`). Testing an existing
  feature branch of this repo: branch from it. Testing only a vc-build version: from
  `origin/main` with `--no-track`.
- vc-build: set `VCBUILD_VERSION` in `actions/setup-vcbuild/index.js` to the new version.
- Point every internal ref at the branch, in `.github/workflows/` **and** `actions/`
  (composite actions call each other, so a workflow pointed at the branch would still
  run tagged copies of nested actions):
  `VirtoCommerce/.github/<path>@<tag>` → `@<branch>`.
- Verify: `git grep -nE 'VirtoCommerce/\.github/[^@ ]+@v[0-9]' -- .github/workflows actions`
  prints only docs (`actions/*/README.md`).
- Line ends: several workflow files are stored with CRLF. Git Bash `sed -i` writes LF,
  and with `core.autocrlf=true` a plain `git add` normalizes too — the diff becomes
  whole files. Restore CR where `git show HEAD:<file>` has it, stage with
  `git -c core.autocrlf=false add`, and check `git diff --cached --stat` counts only
  the changed lines.
- Commit message: `<TICKET>: Test <what> (temporary branch, not for merge)`. Push on OK.

## 3. Choose the target

A failing run or PR given: its repo, at the commit that failed (the PR head). Otherwise
by what changed:

```
change                             target
Compile / Test / Compress / Pack   vc-module-task-management
WebPackBuild, BuildCustomApp       vc-module-task-management
platform build                     vc-platform
playwright, docker-env(-full)      a module with auto-tests
install, InstallModules            the canary's install job
deploy, Cloud* targets             ask first, see below
```

Before running anything there, read the target's workflow:

- Triggers: is there `workflow_dispatch`; which branches `push`/`pull_request` take.
- Side effects on a non-release branch: what a dispatched run publishes (prerelease
  blob, NuGet, GitHub release, Jira links, cloud deploy). Tell the user and get the OK.
- Deployment repositories (vc-deploy-dev branches) and any job that deploys to an
  environment: only on an explicit separate OK, never by default.

## 4. The test branch in the target

- Clone into the scratchpad (`--depth 5 -b <base>`), branch `<same name as step 2>` from
  the failing commit or the default branch.
- In its workflow files, `VirtoCommerce/.github/...@<tag>` → `@<branch of step 2>`.
  Same line-end check as in step 2.
- Commit (`temporary branch, not for merge`), push and dispatch on OK:
  `gh workflow run <workflow> -R <repo> --ref <branch>`.

## 5. Make sure the scenario actually ran

A green run is not the answer until the log shows the path of step 1 was taken:

- The version: `vc-build version: <new>` / `Tool 'virtocommerce.globaltool' (version ...)`.
- The step ran and was not skipped (e.g. `Cache hit: reusing ./publish, skipping vc-build
  install` means the install path was never exercised).
- Caches: `actions/cache` paths under `github.action_path` contain the action ref, so the
  first run on a test branch is cold — default-branch caches never match. Rerunning the
  jobs (`gh run rerun <id> --failed`, or all) after one run saved a cache gives a warm
  start whenever the key differs (restore by prefix), as the docker-env-full publish
  cache does.
- Separate unrelated reds: name the failing step and test, check it against the change,
  rerun once to tell a flake.

## 6. Repros and local checks, where possible

- A/B repro on Linux runners: a temporary `.github/workflows/<slug>-repro.yml` in the
  step 2 branch, `on: push` for that branch only with `paths:` on the file itself, a
  matrix of the old and the new version, numbered scenarios written to
  `GITHUB_STEP_SUMMARY`. GitHub's bash runs with `-e`: collect exit codes with
  `cmd || code=$?`. Expected: the old version fails the bug scenario, the new passes all.
  The file goes away with the branch.
- vc-build locally: install each version with
  `dotnet tool install VirtoCommerce.GlobalTool --version <v> --tool-path <scratchpad>/t<v>`
  (never `--global`), and run the same scenario with both. Limits: some bugs show only on
  Linux; a tool path near 260 characters breaks on Windows with
  `Path '\\?\...' must be rooted` (an artifact of a long scratchpad path, not of
  vc-build); WSL over `/mnt/c` is too slow for installs — use the repro workflow.
- New vc-build: propose a dispatch of the canary,
  `gh workflow run vcbuild-canary.yml --ref main -f version=<new>` — build, install
  and target checks on all runner images, nothing published.
- Workflow changes: `actionlint` and `zizmor` locally if installed.

## 7. Clean up

On OK: delete the test branches in this repo and in the target (remote and local), switch
back to the branch the user was on, remove the scratchpad clones. Runs stay in history,
their links keep working.

## Report

- What was tested and the scenario of step 1.
- A/B table per scenario: old / new version, pass or fail.
- Links: canary run, repro run, live run(s) on the target, with the attempt that took the
  scenario's path.
- What could not be verified and why; unrelated failures with their cause.
- Branches: pushed, cleaned up or still there.
