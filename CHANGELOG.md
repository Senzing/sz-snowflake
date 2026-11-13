# Changelog

All notable changes to this project will be documented in this file.

The changelog format is based on [Keep a Changelog] and [CommonMark].

Versions here are the releases of sz-snowflake, `<senzing_version>-<build>`
(for example `4.4.3-1`): the SENZING® SDK version the release carries and a build counter
that restarts at 1 for each Senzing SDK version.

## [4.4.3-10] - 2026-11-13

### Changed

- Postgres storage starts at 50 GB (`SZ_PG_STORAGE_GB`), and the infrastructure script no
  longer sizes it from `SZ_EXPECTED_RECORDS`. A first load writes write-ahead log faster than
  Postgres archives it: a 1,000,000-record load peaked at 41 GB on disk for 12 GB of data.
  Snowflake grows a nearly full disk on its own, but a few minutes late: a 10 GB disk filled
  first and Postgres stopped. An edited value that is not a whole number of at least 10 GB
  stops the script at I7 (`-20926`) before Postgres is created.
- Removed the `PG_DISK_HIGH` warning and the `PG_STORAGE_GB` setting. Snowflake grows the
  disk without help, and the app only knew the size from install time, so the warning stayed
  on after a grow. `SZ_HEALTH` still shows the database size (`PG_DB_BYTES`).

### Fixed

- `RESOLVE_STATE` no longer reads `CAUGHT_UP` while redo is still being processed. It
  read `CAUGHT_UP` with redo records left, and entity and relationship counts kept
  changing for a minute or more after. The resolver now writes its status when redo
  starts and when it drains, and `CAUGHT_UP` waits for the apply of what redo changed.
  With several resolvers, the newest drain any of them noted counts.
- The install script no longer refuses an edited infrastructure script. Its verify step
  (P1) checked that script's SHA-256 too, and the AI-assisted guide has the assistant edit it
  in the download directory, so the install stopped with `sz-snowflake-infra-<release>.sql:
  FAILED`. It still checks the bundles and itself; the infrastructure script is verified when
  you download it (README "Verify").
- The infrastructure script checks its role first (I0, `-20925`). It stops before creating
  anything when the primary role and the roles it inherits lack `CREATE DATABASE`,
  `CREATE NETWORK POLICY`, `CREATE INTEGRATION` or `CREATE POSTGRES INSTANCE`. A run as
  `SYSADMIN` used to create the database, then fail at I6.

### Documentation

- AI-assisted guide: run as `ACCOUNTADMIN`, and set the assistant's connection role (Cortex
  Code: `SNOWFLAKE_CONNECTIONS_<CONNECTION>_ROLE`), since its shell can carry its own
  session's role into `snow`. Run `--check-only` as well as `--dry-run` before the install.

## [4.4.3-9] - 2026-11-11

### Changed

- The compute pool starts with a node for each container the services start with
  (`RESOLVER_INSTANCES` plus the replicator), not one. Every start and resume used to wait
  about 2 minutes for a second node ("insufficient memory resources").
- From the auto-pause task, an unpause no longer waits in the task for the services. When
  they are not up it starts them, logs `unpause_started` and returns; the next check finishes
  the unpause once Snowflake reports them `READY`. After hours paused, Snowflake took 19 and
  30 minutes to provision the pool's nodes, and the task was billed while it waited.

### Fixed

- A start or resume that times out names the compute pool's state, active and target nodes
  and Snowflake's status message (`DESC COMPUTE POOL`), so a pool still provisioning or out
  of capacity is told apart from a failing service.

## [4.4.3-8] - 2026-11-10

### Added

- `--check-only` on the install script: verifies the release files (signature and checksums),
  unpacks the bundle and checks its contents for real, then stops. It needs no Snowflake
  connection and installs nothing. A `--dry-run` does not unpack the bundle. The release build
  now runs `--check-only` on each architecture's bundle before publishing, so a release whose
  install script cannot accept its own bundle is never published (4.4.3-6 was).
- `SZ_HEALTH` warns `PG_DISK_HIGH` at 75% of the instance's allocated storage, and shows
  `PG_STORAGE_GB` and `PG_DB_BYTES`. The install script sets `PG_STORAGE_GB`.

### Changed

- Paused installs cost much less: the watch and retention tasks are suspended with the app
  (`SZ_SUSPEND`, resumed by `SZ_RESUME`), the auto-pause task checks hourly while paused
  (`SZ_AUTO_PAUSE_PAUSED_CHECK_MINUTES`, 60; every `SZ_AUTO_PAUSE_CHECK_MINUTES` while running)
  and `SZ_SUSPEND` sizes the app warehouse back to X-Small.
- Postgres storage is sized from `SZ_EXPECTED_RECORDS` (twice ~12 KB a record, 10..65535 GB;
  1,000,000 records: 23 GB) instead of a fixed 250 GB; an explicit `SZ_PG_STORAGE_GB` still
  wins. Storage is billed on allocation and never shrinks.

### Fixed

- The install script reads a relative `--license-file` from the directory it was started in. It used to fail at the license step, after the image push, because it reads the license from inside `--assets`.
- A failed `SZ_UNPAUSE` no longer stops auto-pause: when the app is running but `PAUSED_AT` is
  still set, the task clears it and pauses again once idle.
- The install no longer exits 1 after a successful load: `PENDING_OLD` counts only while work
  is live (it read a 10-minute snapshot after `CAUGHT_UP`).
- The app warehouse no longer grows to Medium while idle, and `APPLY_LAG` no longer warns on an
  idle install: both read how long the oldest queued entity had waited when the resolver last
  wrote its status (`SZ_HEALTH.QUEUE_AGE_SECS`), not a statistics estimate or the time since
  the last apply, which grows while idle.
- When Postgres turned read-only (Snowflake grows the disk in read-only mode), the replicator
  could leave a claim it was applying or releasing for the lease sweep, 20 minutes later. A
  read-only error now counts as transient: the replicator retries it and catches up as soon as
  Postgres is writable again. The resolver already retried through it.
- A resolver batch whose keys were all done but whose ids were still being committed stopped
  renewing its lease: a commit stalled longer than the lease (a read-only Postgres) handed the
  batch to a second claim, which ran it again. It now renews until the commit lands.
- An upgrade of a paused install, or one whose image push outlasted the idle window, failed
  with a Postgres connect timeout: auto-pause had suspended Postgres. The install script now
  unpauses a paused install (`SZ_UNPAUSE('install')`) before the steps that need Postgres.

### Documentation

- The app's own page in Snowsight (the application README) follows the Senzing brand and
  editorial rules, matching this repository's README.

## [4.4.3-7] - 2026-11-10

### Fixed

- The 4.4.3-6 install script stopped every real install at P1 with "the bundle lacks
  sz-snowflake-infra-4.4.3-6.sql": it still required the infra and install scripts inside the
  bundle after the release stopped copying them there. It now checks only the bundle's own
  files.
- `--dry-run` with `--loader docker` and the Docker daemon down prints a note instead of
  refusing, the same as a missing tool: a dry run runs nothing.

## [4.4.3-6] - 2026-11-09

### Changed

- A release carries one signature, `SHA256SUMS.sigstore.json`: `SHA256SUMS` is signed and
  holds the SHA-256 of every file, so the per-file `.sigstore.json` files are gone. Verify the
  signature, then `sha256sum -c SHA256SUMS`; the install script does both and refuses a file
  `SHA256SUMS` does not list.
- The bundle no longer copies the infrastructure and install scripts: they are release files
  of their own. A release is 7 files, and an install needs 5 of them.

### Documentation

- The public docs follow the Senzing brand: a logo header, a "How it works" diagram, the
  trademark and editorial rules, and no all-caps labels above headings.
- Use: Postgres storage is billed on what is allocated; Snowflake grows it near full (the
  instance is read-only meanwhile) and never shrinks it.

## [4.4.3-5] - 2026-11-08

### Changed

- Install script: `--skip-verify` is the only flag that skips verification; its older
  alias is removed. It works as before, and only for a bundle you built yourself.

### Fixed

- `SZ_SET_CONFIG` of an instance limit while the services are suspended says
  `applies_at: 'now (suspended services keep it at SZ_RESUME)'`, not 'now (running services)'.

- The comments in the release files (app, infra SQL, install script) and the messages of
  the services read in plain terms; nothing they do changes.

### Documentation

- Install: renewing a license with `SZ_RELOAD_SECRETS` pauses resolution for a few minutes
  (about 2.5 in testing); queries on the crosswalk tables keep working and changes wait in
  the queue.

## [4.4.3-4] - 2026-11-02

### Added

- Install script `--license-file <path>`: the license is checked before any step runs (not
  empty, base64, a multiple of 4 characters) and stored into the license secret before
  setup, never printed.

- `API.SZ_CHECK_LICENSE(<base64>)` checks a license before you store it: an empty or malformed
  value is refused at once (`-20111`), then a short setup job starts the engine with it and
  reports its expiry and record limit, or why the engine refuses it. Nothing is stored or
  restarted; the app never returns or logs the license (it is in the check job's spec while
  the job runs, and the CALL is in your query history).

### Fixed

- Docs: CPU autoscaling does not hold resolvers back when Postgres is the bottleneck, as the
  4.4.3-3 notes and the Use guide said: at 6 threads a resolver waiting on Postgres stays
  above the 40% trigger. The resolver maximum (2 per Postgres core when empty) is what sizes
  them to Postgres; past that ratio the gain is small (+9% for a 5th on `STANDARD_L`), and a
  `RESOLVER_MAX_INSTANCES` set by hand is reached under any load.

- A Postgres resize reaches the running resolvers at once: `SZ_CONFIGURE` and `SZ_SET_CONFIG`
  apply the resolver's instance limits and the pool's `MAX_NODES` to running services when
  `PG_COMPUTE_FAMILY`, `RESOLVER_MAX_INSTANCES`, `RESOLVER_INSTANCES`,
  `REPLICATOR_INSTANCES` or `POOL_MAX_NODES` changes (they used to wait for `SZ_START`). The
  Use guide's resize example now sets only `PG_COMPUTE_FAMILY`; its old 16 resolvers would
  exceed `STANDARD_XL`'s sessions at 6 threads.

## [4.4.3-3] - 2026-11-02

### Added

- The resolver service publishes platform metrics (`container.cpu.usage`, memory) to the account's event table, so its autoscaling can be read against its real CPU.

- `SZ_HEALTH` shows the running license: `LICENSE_EXPIRES`, `LICENSE_DAYS_LEFT`,
  `LICENSE_RECORD_LIMIT`, `LICENSE_RECORDS_USED`, and fails `LICENSE_EXPIRED` and warns
  `LICENSE_EXPIRING` (30 days), `LICENSE_EVALUATION` (the 500-record evaluation limit) and
  `LICENSE_NEAR_LIMIT` (90%).

- A change to a table a mapping view only looks up re-resolves the records that read it:
  a `TABLES` entry with `via` (`{'table': .., 'key_column': .., 'via': {'table': ..,
'key_column': .., 'record_id_column': ..}}`) joins the changed rows to the source table
  that points at them; the install script takes it as `--source-via`. `--source` also takes
  a record id column per table, `<table>=<column>` (a child table's foreign key).

- The install script checks every prerequisite before any step runs (also with `--dry-run`)
  and lists every problem at once, changing nothing: the tools on PATH, the Snowflake CLI's
  connector version, the Docker daemon, `--pg-host` resolving, the bundle and `SHA256SUMS`,
  the connection and role, the infra secrets and external access integration, and each
  `--source` view (`DATA_SOURCE`, `RECORD_ID`, `RECORD_JSON`) and table (visible,
  `CHANGE_TRACKING` on, the record id column).

### Changed

- Default engine threads are 6 per CPU (was 4): a 4-thread resolver used about half its CPU,
  its threads waiting on Postgres.
- `RESOLVER_MAX_INSTANCES` and `POOL_MAX_NODES` default to empty, derived from Postgres:
  2 resolver CPUs per core of `PG_COMPUTE_FAMILY` (4 on `STANDARD_L`, 8 on `STANDARD_XL`;
  4 when unknown), and a pool node for each plus the replicator and setup job. On
  `STANDARD_L` a 5th resolver took Postgres from load 7 to 18 for 9% more throughput.
  An upgrade resets a value still at the old default (7, 9) to empty. The install script
  sets `PG_COMPUTE_FAMILY` from the Postgres instance.

- Resolver autoscaling adds an instance above 40% CPU (was 50%) and removes one below 25%
  (was 30%). A resolver not waiting on Postgres averages about 48%, so 50% held the second
  resolver back 18 minutes in a 200,000-record first load; resolvers waiting on a saturated
  Postgres stay below 40%, so the database is still not overloaded.

- **Breaking:** a mapping view's JSON column is now `RECORD_JSON` (was `JSON_DOC`), so a
  view is `DATA_SOURCE`, `RECORD_ID`, `RECORD_JSON` — the contract the Senzing MCP server's
  Snowflake guidance already uses. No alias: before upgrading, rename the column in each
  registered mapping view (`... AS RECORD_JSON`); a view still returning `JSON_DOC` is
  refused by `SZ_REGISTER_SOURCE` and cannot be resolved.

### Fixed

- `SZ_REGISTER_SOURCE` upper-cases a plain `record_id_column` (and a `via` entry's columns)
  like Snowflake does for unquoted names; a lower-case name used to register but never
  match a changed row.

- The install script's wait for `CAUGHT_UP` no longer stops silently: a failed
  `SZ_HEALTH` poll is reported and retried, and the wait always ends with one
  `resolve wait:` line naming the outcome (`CAUGHT_UP`, timed out, failed source,
  error), the elapsed time, records and entities resolved, `SZ_HEALTH.OVERALL` and the
  exit code. A timeout says resolution continues in the background.

## [4.4.3-2] - 2026-10-31

### Added

- Auto-pause, on by default: an install idle for 30 minutes suspends its compute pool and
  Postgres and wakes on new work; `SZ_PAUSE` / `SZ_UNPAUSE` in `SZ_INFRA_DB.SZ_INFRA`.
  `SZ_PG_SHARED` marks a Postgres as shared (never suspended); `SZ_PG_MODE EXTERNAL` uses
  your own PostgreSQL 17.
- Two installs in one account (`--app`, `--infra-prefix`); `SZ_UNINSTALL`,
  `SZ_PURGE_SOURCE`, `RESOLVE_STATE`, and FAIL/WARN codes in `SZ_HEALTH`.
- Per-architecture bundles (`linux-amd64`, `linux-arm64`, about 0.31 GB each).
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
