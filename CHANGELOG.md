# Changelog

All notable changes to this project will be documented in this file.

The changelog format is based on [Keep a Changelog] and [CommonMark].

Versions here are the releases of Senzing on Snowflake, `<senzing_version>-<build>`
(for example `4.4.3-1`): the Senzing version the release carries and a build counter
that restarts at 1 for each Senzing version.

## [Unreleased]

### Added

- `sz-snowflake-cord-data.tar.gz`, the CORD data for the Senzing Snowflake preview: Senzing's
  official [CORD](https://senzing.com/senzing-ready-data-collections-cord/) data from its Las Vegas collection, reshaped into normalized source
  tables for six source systems (about 200,000 records), with `load.sql` to load it into
  Snowflake. For trying the app without data of your own; the tables must be mapped to
  Senzing before they are registered.

## [4.4.3-1] - 2026-10-30

### Added

- Public Preview: sz-snowflake is provided as-is, without warranty or a support commitment;
  interfaces, settings and release files can change between releases.
- `docs/ai-assisted.md`: install, resolve and report with an AI assistant (Snowflake Cortex
  Code, Claude Code): two prompts, the Senzing MCP server, and a local Streamlit report on
  your data joined with the results.
- The release bundles `sz-snowflake-<release>-linux-<arch>.tar.gz`, one per architecture:
  the Snowflake Native App files, the three container images (`sz-snowflake-setup`,
  `-resolver`, `-replicator`; distroless, uid 65532, built natively for `linux/amd64` and
  `linux/arm64`) as one docker archive, the
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
- Sizing for a load: the resolvers scale out on CPU up to `RESOLVER_MAX_INSTANCES` and the
  compute pool adds the cheapest nodes (`GEN_ARM_G1_2`, 1 vCPU, 6 GiB) to fit them; smaller batches (1,000 to 5,000 keys); every
  configuration is checked against a pool node and the Postgres connection budget
  (`PG_COMPUTE_FAMILY`, `-20024`); the infrastructure script creates Postgres with JIT off
  and prints the load sizing; `SZ_HEALTH` names Postgres connection failures
  (`PG_UNREACHABLE`, `STARTING_STUCK`). Postgres needs at least 8 GB (`STANDARD_L` or
  larger): a smaller `PG_COMPUTE_FAMILY` or `SZ_PG_FAMILY` is refused and `SZ_HEALTH` fails
  `PG_TOO_SMALL`; burstable families are not supported. See
  [Sizing](docs/use.md#sizing).
- One bundle per architecture, `sz-snowflake-<release>-linux-<arch>.tar.gz` (about 0.3 GB;
  was one 1.8 GB bundle with both): download only the one for your compute pool. The three
  images travel as one archive per architecture, their shared layers stored once.
- Source tables need change tracking: `SZ_REGISTER_SOURCE` refuses a table without it
  (`-20208`) with the exact `ALTER TABLE .. SET CHANGE_TRACKING = TRUE;`, and
  `RESOLVE_STATE` reads `SOURCES_FAILED` (never `CAUGHT_UP`) while a source's capture fails.
  Setup warns when `PG_DATABASE` already holds an earlier install's records
  (`EXISTING_RECORDS`). The install script can be re-run (bindings already made are kept).
- Bring your own PostgreSQL 17: the infrastructure script's `SZ_PG_MODE = 'EXTERNAL'` (with
  `SZ_PG_HOST`, `SZ_PG_PORT`) skips Snowflake Postgres and prints the `CREATE SECRET`
  statements for you to run; `PG_COMPUTE_FAMILY` `EXTERNAL` with `PG_MEMORY_GIB` and
  `PG_MAX_CONNECTIONS` keeps the 8 GB minimum and the connection budget; setup refuses a
  server older than PostgreSQL 17. See install's "Bring your own PostgreSQL" and "Same region
  is required".
- `SZ_PURGE_SOURCE('<CODE>')` removes every record of a data source (after `SZ_UNREGISTER_SOURCE`),
  for example an earlier install's records; `SZ_HEALTH.PURGES` shows its progress.
- Two installations in one account: the app names its compute pool and warehouse after
  itself (`<APP>_POOL`, `<APP>_WH`), the infrastructure script's `SZ_PREFIX` names its
  objects, and the install script takes `--app` and `--infra-prefix`.
- `SZ_PG_SHARED = 'YES'` in the infrastructure script: for a Postgres instance other workloads
  use, pausing suspends only the app's services and pool, never Postgres.
- A re-run of the install script with a new bundle upgrades the installed app itself;
  `SZ_HEALTH.FAIL_CODES` names what makes `OVERALL` fail.
- The install script takes `--role`, explains a P2 privilege failure, shows push progress,
  and registers a new patch when a rebuilt bundle reuses a release's label (it ran the older
  build).
- Pause to save money: `SZ_INFRA_DB.SZ_INFRA.SZ_PAUSE()` / `SZ_UNPAUSE()` suspend and resume
  the app and your Postgres instance; auto-pause, on by default (`SZ_AUTO_PAUSE`,
  `SZ_IDLE_PAUSE_MINUTES` = 30, checked every `SZ_AUTO_PAUSE_CHECK_MINUTES` = 10), pauses an
  idle install and resumes it when changes arrive; the app's health task does no work
  while paused.
- `SZ_UNINSTALL('<PG_DATABASE>')`: drops the Senzing database in your Postgres before
  `DROP APPLICATION`, which cannot reach it; `SHOW SERVICES IN APPLICATION` now lists the
  services for `APP_ADMIN`.
- `sign-release.yaml`, which checks a published release's files against `SHA256SUMS` and
  signs each one keyless as this repository's workflow.
- Repository scaffolding: CODEOWNERS, Dependabot, linter configuration, spellcheck
  and project-board automation.

[CommonMark]: https://commonmark.org/
[Keep a Changelog]: https://keepachangelog.com/
