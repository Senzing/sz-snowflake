# Changelog

All notable changes to this project will be documented in this file.

The changelog format is based on [Keep a Changelog] and [CommonMark].
This project adheres to [Semantic Versioning].

Versions here are the versions of the published container image, which are the
versions of the payload release that produced it. Nothing has been released
yet, so every entry below is unreleased.

## [Unreleased]

### Added to Unreleased

- `Dockerfile` for the Senzing on Snowflake evaluation container, on
  `senzing/senzingsdk-runtime` pinned by tag and digest, building
  `linux/amd64` only and running as uid 1001. Everything below its payload
  section is a placeholder.
- `docker-build-and-publish.yaml`, which builds the image on every pull
  request, builds, pushes, signs and attests it to
  `ghcr.io/senzing/sz-snowflake` when a release is published, and can be run
  manually to point `:latest` back at the highest published version.
- Repository scaffolding: CODEOWNERS, Dependabot, linter configuration,
  spellcheck, project-board automation and the Claude attribution check.

[CommonMark]: https://commonmark.org/
[Keep a Changelog]: https://keepachangelog.com/
[Semantic Versioning]: https://semver.org/
