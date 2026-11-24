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

Only when the `.NET` base image version (`mcr.microsoft.com/dotnet/aspnet:<version>`) or
the `wkhtmltopdf` version needs to change — both rare. Keep this in sync with whatever
`vc-docker`'s platform Dockerfile currently uses for those two things. If `vc-docker` ever
changes the boilerplate part (the `find`/`cp` logic, `WORKDIR`, etc.), update
`docker-env-full/Dockerfile.platform` to match — it's not automatically synced.

## Build and publish

`wait-for-it.sh` is not committed here (see `actions/.gitignore`): fetch it from
`vc-docker`'s `feat/net10` branch right before the build, so the image gets the copy
`vc-docker` currently ships. Fetch it by commit, not by branch name, and record that commit
in the image label, so `docker inspect` shows which copy is inside.

```sh
cd docker-env-full/base-image
VC_DOCKER_SHA=$(gh api repos/VirtoCommerce/vc-docker/commits/feat/net10 --jq .sha)
curl -fsSLo wait-for-it.sh "https://raw.githubusercontent.com/VirtoCommerce/vc-docker/$VC_DOCKER_SHA/linux/platform/wait-for-it.sh"
docker build --label "com.virtocommerce.vc-docker.revision=$VC_DOCKER_SHA" -t ghcr.io/virtocommerce/platform-base:10.0-wkhtmltopdf .
docker push ghcr.io/virtocommerce/platform-base:10.0-wkhtmltopdf
docker inspect --format='{{index .RepoDigests 0}}' ghcr.io/virtocommerce/platform-base:10.0-wkhtmltopdf
```

Requires push access to the `VirtoCommerce` GitHub Container Registry namespace. This is a
manual/occasional step for now, not wired into any CI workflow — automating it (e.g. a
scheduled or manually-triggered `workflow_dispatch` in this repo) is a reasonable follow-up
once this approach is confirmed to actually help on a real run.
Local push from developer's machine can use gh token: `echo $(gh auth token) | docker login ghcr.io -u <your-github-username> --password-stdin`, then change package visibility to `public` at https://github.com/orgs/VirtoCommerce/packages/container/package/platform-base.

After pushing, update both `platformBaseImage` defaults (`docker-env/action.yml`,
`docker-env-full/action.yml`, and the `docker-env` README) to the digest printed above
(`ghcr.io/virtocommerce/platform-base:10.0-wkhtmltopdf@sha256:...`) in a pull request. The
floating tag alone can be overwritten by a later push, which would change every module's CI
at once without review or release; with the digest, a new base image reaches modules only
through that PR and the next release.
