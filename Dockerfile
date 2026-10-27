# Senzing on Snowflake -- evaluation container.
#
# PLACEHOLDER. The build pipeline around this file is finished; the recipe in
# it is not. Everything below the "payload" section is a starting point for
# whoever owns the image contents, not a reviewed choice.
#
# What the pipeline guarantees you can rely on:
#
#   * `./payload/` exists in the build context when this file is built by
#     .github/workflows/docker-build-and-publish.yaml. It is the unpacked,
#     checksum-verified release asset attached to this repository's own
#     releases. Before the first release exists it contains a single STUB
#     file instead, so the Dockerfile is still exercised on day one.
#
#   * The build is linux/amd64 only. Snowpark Container Services runs amd64;
#     an arm64 layer would never be pulled. UNVERIFIED and worth settling
#     before anyone adds a platform: whether Snowflake's image repository
#     accepts a multi-platform manifest list at all.

# Tag AND digest -- the same pin other Senzing repositories already carry for
# this base image. The tag is what a human reads, the digest is what resolves,
# so a moved tag cannot change what this builds. The digest is the OCI image
# INDEX rather than a per-architecture manifest, so `platforms: linux/amd64`
# in docker-build-and-publish.yaml still picks the amd64 child out of it.
#
# LITERAL, NOT `FROM ${BASE_IMAGE}`, and that is not a style preference.
# checkov's CKV_DOCKER_7 does not expand ARG defaults: ANY `FROM ${VAR}` fails
# it however the ARG is pinned. Measured against checkov 3.3.1 -- the same
# file passes with the reference inline and fails with it behind an ARG.
# Nothing passes a --build-arg here, so the indirection bought nothing. Put it
# back and the required check goes red.
#
# STILL UNVERIFIED: that senzingsdk-runtime is the right base for a
# Senzing-on-Snowflake evaluation container at all. It is the plausible one,
# not a reviewed choice. Only the floating-tag half of that is settled here.
FROM senzing/senzingsdk-runtime:4.4.2@sha256:1f86d22ca02fe4558010420d76e64c8536a9c6dc53783ddda3da5dfda34d5fb9

# These labels are not decoration. `org.opencontainers.image.source` is what
# links the pushed package to this repository on GitHub, which is what makes
# the package inherit the repository's access and show up on its page. Without
# it the package lands in the organization unattached.
LABEL org.opencontainers.image.source="https://github.com/Senzing/sz-snowflake"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.title="sz-snowflake"
LABEL org.opencontainers.image.description="Senzing on Snowflake evaluation container"
LABEL org.opencontainers.image.vendor="Senzing"

# Deliberately NOT labelled: anything naming where the payload was built.
# Labels ship inside a public image, and the image config also publishes
# ARG/ENV values through its layer history regardless of any provenance
# setting -- so nothing about the payload's origin may be passed as a build
# arg either.

# ---------------------------------------------------------------------------
# Non-root user
# ---------------------------------------------------------------------------
# The base image runs as root and defines no other account -- it ends on
# `USER root`. So this creates one rather than switching to an existing one.
# uid 1001 is the house number: several Senzing images over this same base
# create it with this same `useradd` line and end on `USER 1001`.
RUN useradd --no-log-init --create-home --shell /bin/bash --uid 1001 --user-group senzing

# ---------------------------------------------------------------------------
# Payload
# ---------------------------------------------------------------------------
# `--chown` because the USER below cannot write to a root-owned /app.
# /app IS THE ONLY DIRECTORY THIS FILE GIVES THE RUNTIME USER: if the real
# payload writes anywhere else, that directory has to be created and given to
# the same user here, or it fails at runtime rather than at build time. /tmp
# is world-writable in the base image and needs nothing.
COPY --chown=senzing:senzing payload/ /app/

# ---------------------------------------------------------------------------
# Everything below here is Brian's to replace.
# ---------------------------------------------------------------------------
WORKDIR /app

# PLACEHOLDER HEALTHCHECK -- REPLACE IT. There is no service here yet, so this
# asserts the only thing that is true of the image today: that the Senzing
# runtime it exists to carry is installed. It says nothing about the payload.
# The base image sets this very check itself and it is inherited at runtime;
# restating it is what makes it visible to checkov (CKV_DOCKER_2) and trivy
# (DS-0026), which read this file and not the base image's config.
# senzingsdk-tools does the same thing for its own package.
HEALTHCHECK CMD apt list --installed | grep senzingsdk-runtime

USER senzing

# Snowpark Container Services mounts a session token at
# /snowflake/session/token for the container to authenticate back to Snowflake.
# Whatever runs here reads it rather than carrying a credential of its own.
#
# FOR BRIAN: that mount arrives owned by root, and this container no longer
# runs as root. Whether uid 1001 can read it is UNVERIFIED -- it is the first
# thing to check if authentication fails.

CMD ["/bin/sh", "-c", "echo 'sz-snowflake: no entrypoint configured yet' && ls -la /app && sleep infinity"]
