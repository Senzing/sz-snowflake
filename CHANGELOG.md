# Changelog

All notable changes to this project will be documented in this file.

The changelog format is based on [Keep a Changelog] and [CommonMark].

Versions here are the releases of Senzing on Snowflake, `<senzing_version>-<build>`
(for example `4.4.3-1`): the Senzing version the release carries and a build counter
that restarts at 1 for each Senzing version.

## [Unreleased]

Nothing yet.

## [4.4.3-1] - 2026-10-30

### Added

- Public Preview: sz-snowflake is provided as-is, without warranty or a support commitment;
  interfaces, settings and release files can change between releases.
- `docs/ai-assisted.md`: install, resolve and report with an AI assistant (Snowflake Cortex
  Code, Claude Code): two prompts, the Senzing MCP server, and a local Streamlit report on
  your data joined with the results.
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
- Easier install and run: register a source by naming its mapping view and tables
  (`SZ_REGISTER_SOURCE('<CODE>', '<db.schema.view>', ['<db.schema.table>'])`, no reference
  alias lookup); configure the Postgres host and settings in one checked call
  (`SZ_CONFIGURE({..})`); a done signal, `SZ_HEALTH.RESOLVE_STATE` (`CAUGHT_UP` once
  everything captured is resolved); setup progress while `SZ_SETUP` runs
  (`SZ_HEALTH.SETUP_PHASE`) and its timing by phase afterwards; the install script's
  `--source` registers sources and waits until they are resolved.
- `sign-release.yaml`, which checks a published release's files against `SHA256SUMS` and
  signs each one keyless as this repository's workflow.
- Repository scaffolding: CODEOWNERS, Dependabot, linter configuration, spellcheck
  and project-board automation.

[CommonMark]: https://commonmark.org/
[Keep a Changelog]: https://keepachangelog.com/
