# Platform base image

Pre-baked base for the platform image built by `docker-env-full`'s two Dockerfile-build
branches (`customPackagesJsonUrl` / `installCustomModule`) and by `docker-env`'s
`installCustomModule` branch. See the comment at the top of
`Dockerfile` in this directory for why this exists — in short: `vc-docker`'s platform
Dockerfile installs `wkhtmltopdf` via `apt-get` *after* the always-changing `COPY publish`
layer, so it can never be a Docker layer-cache hit there. Baking it into its own image,
pulled via a plain `docker pull` instead of built, sidesteps that: pulls from `ghcr.io` are
fast (measured 3-8s for comparable images in this pipeline), and a plain `docker build`
against this base has no build-time cost of its own — it's already sitting in the local
image cache once pulled.

`docker-env-full/Dockerfile.platform` builds `FROM` this (via a `BASE_IMAGE` build-arg) —
it's a small, static Dockerfile owned in this repo, not downloaded from `vc-docker` and
patched. The only part of the platform image that actually varies per build is the
`COPY publish` content itself; everything else (that `COPY`, the runtimes `find`/`cp`,
`WORKDIR`/`EXPOSE`/`ENV`/`ENTRYPOINT`) is generic boilerplate, so it's simpler and more
robust to own a copy of it than to regex-patch someone else's file on every build.

## When to rebuild

`.github/workflows/platform-base-image.yml` rebuilds and publishes the image:

- on the 1st of every month, to pick up the current `aspnet:10.0` patch and Ubuntu security
  updates (`apt-get upgrade`);
- on every push to `main` that changes this directory, except `.md` files;
- by hand (`workflow_dispatch`); with `promote` off it stops after the tests and leaves the
  floating tag where it is. `promote` is allowed from `main` only: a run from another branch
  with `promote` on fails at once.

Both `platformBaseImage` defaults (`docker-env`, `docker-env-full`) use the floating
`10.0-wkhtmltopdf` tag, so moving it changes every module's CI at once, without a release.
The workflow therefore:

1. builds the image, smoke-tests it and pushes it under a dated tag only
   (`10.0-wkhtmltopdf-<yyyymmdd>-<run>-<attempt>`);
2. runs the Playwright auto-tests (`playwright-tests.yml`, all three databases) with that
   build as `platformBaseImage`, installing `vc-module-catalog`'s latest release on the latest
   bundle — the same path module CI takes;
3. only if they pass, points `10.0-wkhtmltopdf` at the tested manifest.

The tests build the platform image with the `docker-env-full` release that
`playwright-tests.yml` pins, not with this commit's `Dockerfile.platform`. They check the new
base against what module CI runs today; a change to `Dockerfile.platform` is covered by the
release that ships it.

A failed test leaves the floating tag on the previous image; rerun the failed jobs to retry
(the SQL Server suite has known flaky deletes). The image carries the number of the run that
built it, and promote never moves the tag to an image from an older run than the current
one, so a late re-run of an old run cannot roll the tag back. Only one run that can promote
waits at a time: a newer one replaces a waiting one, which is harmless since both build
`main`. The run summary prints the previous digest and the command to move the tag back.

The image records what it was built from: `org.opencontainers.image.base.name` (the
`aspnet:10.0` digest), `org.opencontainers.image.revision` (this repo's commit) and
`com.virtocommerce.vc-docker.revision` (the vc-docker commit `wait-for-it.sh` came from).

If `vc-docker` changes the boilerplate part of its platform Dockerfile (the `find`/`cp`
logic, `WORKDIR`, etc.), update `docker-env-full/Dockerfile.platform` to match — it's not
automatically synced.

Publishing needs the `platform-base` package to grant this repository Write access
(package settings > Manage Actions access): the package was first pushed by hand and is not
linked to a repository.

## Trying a change

Run the workflow by hand with `promote` off: it builds, pushes a dated tag and runs the
auto-tests without touching `10.0-wkhtmltopdf`. Do not push that tag by hand — it skips the
tests and changes every module's CI at once.

To build locally: `wait-for-it.sh` is not committed here (see `actions/.gitignore`), so fetch
it from `vc-docker`'s `feat/net10` branch by commit first. Without
`--build-arg ASPNET_IMAGE=...` the build uses the `aspnet:10.0` digest pinned in the
Dockerfile.

```sh
cd actions/docker-env-full/base-image
VC_DOCKER_SHA=$(gh api repos/VirtoCommerce/vc-docker/commits/feat/net10 --jq .sha)
curl -fsSLo wait-for-it.sh "https://raw.githubusercontent.com/VirtoCommerce/vc-docker/$VC_DOCKER_SHA/linux/platform/wait-for-it.sh"
docker build --label "com.virtocommerce.vc-docker.revision=$VC_DOCKER_SHA" -t platform-base:local .
```
