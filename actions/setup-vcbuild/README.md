# setup-vcbuild

Installs vc-build (`VirtoCommerce.GlobalTool`) of the version pinned in [index.js](index.js) (`VCBUILD_VERSION`).

## Example of usage

```yaml
- name: Setup vc-build
  uses: VirtoCommerce/.github/actions/setup-vcbuild@v3.1000.1
```

To try another vc-build version, for example a prerelease, in a pilot repository:

```yaml
- name: Setup vc-build
  uses: VirtoCommerce/.github/actions/setup-vcbuild@v3
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

## How a new vc-build version gets to the module repos

Every workflow and action in this repository installs vc-build through this action, so the version is pinned in one place, and the module repos get a new vc-build only with a new tag of this repository. A stable vc-build release on NuGet changes nothing by itself.

1. vc-build publishes a prerelease (`3.x.y-alpha.n`).
2. Run the [vc-build canary](../../.github/workflows/vcbuild-canary.yml) workflow with `version` = that prerelease. On ubuntu-22.04, ubuntu-24.04 and ubuntu-latest it builds the release branch (`master`) of vc-module-task-management (a module with an AngularJS admin UI and a custom app) and vc-platform (`ChangeVersion`, `Compile`, `Test` (task-management only), `Compress`, `Pack`, `IncrementPatch`) and installs modules and a platform the way vc-deploy-dev and docker-env do (`InstallModules`, `install -Edge`, `install` from a package manifest). It also checks that every target the workflows call still exists, including the ones that publish and so cannot run here, and, except on pull requests, reads the `vcptcore-dev` cloud environment with `CloudEnvStatus`. Nothing is published or deployed.
3. Optional, for bigger changes: pilot PRs in vc-module-task-management and vc-platform with `version:` set as above, to run their full CI (auto-tests, swagger validation). Close them after the run.
4. vc-build publishes the stable version.
5. Bump `VCBUILD_VERSION` in [index.js](index.js) to it. The pull request runs the canary on the new version.
6. Release this repository (`/release`) and deploy the workflows to the module repos.

The module repos use an exact tag (`@v3.1000.10`). The deployment repositories (the vc-deploy-dev branches) use the floating `@v3` tag, which `/release` moves to every new release, so they get the new vc-build with the release and need no commits of their own:

```yaml
- name: Install vc-build
  uses: VirtoCommerce/.github/actions/setup-vcbuild@v3
```

Rollback: deploy the previous tag of this repository to the module repos, and move `v3` back to it.

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
