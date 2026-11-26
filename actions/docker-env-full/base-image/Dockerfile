# Pre-baked base for the platform image that docker-env-full's Dockerfile-build branches and
# docker-env's custom-module branch build with Dockerfile.platform. Mirrors vc-docker's
# platform Dockerfile static prefix (FROM image, wait-for-it.sh, wkhtmltopdf apt-get) so
# per-run builds only do `COPY publish` + find/cp, skipping the apt-get every time.
#
# Rebuilt by .github/workflows/platform-base-image.yml (monthly, and on changes here), which
# passes the current aspnet:10.0 digest as ASPNET_IMAGE and moves the floating tag only after
# the auto-tests pass. The default below is only for a manual build — see README.md.
ARG ASPNET_IMAGE=mcr.microsoft.com/dotnet/aspnet:10.0@sha256:f1126d438ccc359f51cc6d4701a8deae513856cf10f5fe645d29ea6403dcac6b
FROM ${ASPNET_IMAGE}

# upgrade: security updates of the Ubuntu packages, as vc-docker's Dockerfile does per build.
RUN apt-get update && \
    apt-get upgrade -y --no-install-recommends && \
    apt-get install -y --no-install-recommends wkhtmltopdf=0.12.6-2build2 && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    wkhtmltopdf --version

COPY wait-for-it.sh /wait-for-it.sh
RUN chmod +x /wait-for-it.sh
