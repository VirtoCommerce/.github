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
- on every push to `main` that changes this directory;
- by hand (`workflow_dispatch`); with `publish` off it only builds and smoke-tests.

Each publish pushes `10.0-wkhtmltopdf` and a dated tag (`10.0-wkhtmltopdf-<yyyymmdd>-<run>`),
then opens a pull request that points both `platformBaseImage` defaults
(`docker-env/action.yml`, `docker-env-full/action.yml`, and the `docker-env` README) at the
new digest. The defaults are pinned by digest, so a push to the floating tag does not change
any module's CI: a new base image reaches modules only through that PR and the next release.
Run module CI on a module with the PR branch before merging it.

The image records what it was built from: `org.opencontainers.image.base.name` (the
`aspnet:10.0` digest), `org.opencontainers.image.revision` (this repo's commit) and
`com.virtocommerce.vc-docker.revision` (the vc-docker commit `wait-for-it.sh` came from).

If `vc-docker` changes the boilerplate part of its platform Dockerfile (the `find`/`cp`
logic, `WORKDIR`, etc.), update `docker-env-full/Dockerfile.platform` to match — it's not
automatically synced.

Publishing needs the `platform-base` package to grant this repository Write access
(package settings > Manage Actions access): the package was first pushed by hand and is not
linked to a repository.

## Manual build

`wait-for-it.sh` is not committed here (see `actions/.gitignore`): fetch it from
`vc-docker`'s `feat/net10` branch by commit, and record that commit in the image label.
Without `--build-arg ASPNET_IMAGE=...` the build uses the `aspnet:10.0` digest pinned in the
Dockerfile.

```sh
cd docker-env-full/base-image
VC_DOCKER_SHA=$(gh api repos/VirtoCommerce/vc-docker/commits/feat/net10 --jq .sha)
curl -fsSLo wait-for-it.sh "https://raw.githubusercontent.com/VirtoCommerce/vc-docker/$VC_DOCKER_SHA/linux/platform/wait-for-it.sh"
docker build --label "com.virtocommerce.vc-docker.revision=$VC_DOCKER_SHA" -t ghcr.io/virtocommerce/platform-base:10.0-wkhtmltopdf .
```

Prefer the workflow for publishing: it smoke-tests the image and opens the digest PR.
