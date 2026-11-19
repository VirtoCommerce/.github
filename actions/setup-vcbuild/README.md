# setup-vcbuild

Installs vc-build (`VirtoCommerce.GlobalTool`) of the version pinned in [index.js](index.js) (`VCBUILD_VERSION`).

## Example of usage

```yaml
- name: Setup vc-build
  uses: VirtoCommerce/.github/actions/setup-vcbuild@stable
```

To try another vc-build version, for example a prerelease, in a pilot repository, or to hold a repository on a fixed version:

```yaml
- name: Setup vc-build
  uses: VirtoCommerce/.github/actions/setup-vcbuild@stable
  with:
    version: 3.1002.0-alpha.301
```

The `version` input exists from the release that adds it (VCST-6856): an older tag ignores it with an "Unexpected input" warning and installs its own pinned version.

| Input | Default | Description |
| --- | --- | --- |
| `version` | the pinned version | vc-build version to install instead of the pinned one |

| Output | Description |
| --- | --- |
| `version` | The vc-build version that was installed |

## The `stable` tag

Every workflow and template in this repository, and the deployment repositories (the vc-deploy-dev branches), call this action as `setup-vcbuild@stable`, a floating tag that is moved only to change the vc-build version. So the version is pinned in one place, and a new vc-build reaches the module repos and the deployment repositories when `stable` moves: no new tag of this repository and no deploy of the workflows. A stable vc-build release on NuGet changes nothing by itself.

`stable` is for this action only. The other actions and the reusable workflows are referenced by an exact tag (`@v3.1000.x`); do not reference them `@stable`, it would give them whatever code that commit had.

The flip side: rerunning an old build, or a hotfix release of an old version, gets the current vc-build, not the one it was built with. If an old branch needs the old vc-build, set `version:` (above) in its workflow.

## How a new vc-build version gets to the module repos

1. vc-build publishes a prerelease (`3.x.y-alpha.n`).
2. Run the [vc-build canary](../../.github/workflows/vcbuild-canary.yml) workflow with `version` = that prerelease. On ubuntu-22.04, ubuntu-24.04 and ubuntu-latest it builds the release branch (`master`) of vc-module-task-management (a module with an AngularJS admin UI and a custom app) and vc-platform (`ChangeVersion`, `Compile`, `Test` (task-management only), `Compress`, `Pack`, `IncrementPatch`) and installs modules and a platform the way vc-deploy-dev and docker-env do (`InstallModules`, `install -Edge`, `install` from a package manifest). It also checks that every target the workflows call still exists, including the ones that publish and so cannot run here, and, except on pull requests, reads the `vcptcore-dev` cloud environment with `CloudEnvStatus`. Nothing is published or deployed.
3. Optional, for bigger changes: pilot PRs in vc-module-task-management and vc-platform with `version:` set as above, to run their full CI (auto-tests, swagger validation). Close them after the run.
4. vc-build publishes the stable version.
5. Bump `VCBUILD_VERSION` in [index.js](index.js) to it. The pull request runs the canary on the new version.
6. Merge it and move `stable` to the merge commit (`/release vc-build`). From the next run on, every module build and deployment installs the new version.

Rollback: move `stable` back to the commit it was on before. The message of each annotated `stable` tag names its vc-build version.

The canary also runs nightly on the pinned version and posts to Teams when it fails: that is how a new runner image that breaks vc-build shows up before a module build or a deployment fails.

## Compile action

Use @vercel/ncc tool to compile your code and modules into one file used for distribution.

- Install vercel/ncc by running this command in your terminal.

```bash
npm i -g @vercel/ncc
```

- Compile your index.ts file.

```bash
ncc build ./src/index.ts --license licenses.txt
```
