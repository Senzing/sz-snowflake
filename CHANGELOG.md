# Changelog

All notable changes to this project will be documented in this file.

The changelog format is based on [Keep a Changelog] and [CommonMark].

Versions here are the releases of Senzing on Snowflake, `<senzing_version>-<build>`
(for example `4.4.2-7`): the Senzing version the release carries and a build counter
that restarts at 1 for each Senzing version. Nothing has been released yet, so every
entry below is unreleased.

## [Unreleased]

### Added to Unreleased

- The release bundle `sz-snowflake-<release>.tar.gz`: the Snowflake Native App files, the
  three container images (`sz-snowflake-setup`, `-resolver`, `-replicator`; distroless,
  uid 65532, built natively for `linux/amd64` and `linux/arm64`) as docker archives, the
  infrastructure script and the install script. The infrastructure script and the install
  script are also attached on their own, with `SHA256SUMS` and a cosign signature for
  each file.
- The guide: [README](README.md), [install](docs/install.md), [use](docs/use.md)
  and [troubleshooting](docs/troubleshooting.md).
- In-app acceptance of the Senzing End User License Agreement:
  `CALL SZ_SNOWFLAKE.API.SZ_ACCEPT_EULA('I_ACCEPT_THE_SENZING_EULA')` (`APP_ADMIN`), required
  before `SZ_SETUP` and `SZ_START` (`-20109`) and shown in `SZ_HEALTH` (`EULA_NOT_ACCEPTED`);
  the install script's `--accept-eula` runs it.
- `sign-release.yaml`, which checks a published release's files against `SHA256SUMS` and
  signs each one keyless as this repository's workflow.
- Repository scaffolding: CODEOWNERS, Dependabot, linter configuration, spellcheck
  and project-board automation.

[CommonMark]: https://commonmark.org/
[Keep a Changelog]: https://keepachangelog.com/
