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

ARG BASE_IMAGE=senzing/senzingsdk-runtime:latest
# UNVERIFIED: the base above is the plausible one for a Senzing evaluation
# container, not a reviewed decision. Pin it to a digest once it is settled --
# a floating tag in a published image is a moving dependency.

FROM ${BASE_IMAGE}

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
# Payload
# ---------------------------------------------------------------------------
COPY payload/ /app/

# ---------------------------------------------------------------------------
# Everything below here is Brian's to replace.
# ---------------------------------------------------------------------------
WORKDIR /app

# Snowpark Container Services mounts a session token at
# /snowflake/session/token for the container to authenticate back to Snowflake.
# Whatever runs here reads it rather than carrying a credential of its own.

CMD ["/bin/sh", "-c", "echo 'sz-snowflake: no entrypoint configured yet' && ls -la /app && sleep infinity"]
