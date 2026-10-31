<p>
  <img src="../assets/senzing-logo.jpg" alt="Senzing" width="48" align="left" hspace="8">
  <samp><b>SENZING</b></samp>
</p>
<br clear="left">

[sz-snowflake](../README.md) / Install

# Install

**From a signed release to a running app, in your own Snowflake account.** You are both
the provider and the consumer of the app; everything happens in your account. Start with
the [README](../README.md): prerequisites and how to verify the release files.

Download one release's files into a directory and run the steps from there. Replace
`<release>` with the release, for example `4.4.3-1`.

<sub><b>YOUR INFRASTRUCTURE</b></sub>

## 1. Run the infrastructure script

`sz-snowflake-infra-<release>.sql`: you run it, you own everything it creates, and you can
change any of it later. **Read every statement before you run it.** It is re-runnable,
never prints a secret, and ends with a verification query.

| It creates | Review |
|---|---|
| `SZ_INFRA_DB.SZ_INFRA` (`<SZ_PREFIX>_INFRA_DB`; the prefix, default `SZ`, also names `SZ_PG`, `SZ_PG_POLICY` and `SZ_PG_EAI`) | home for your rules, secrets, procedure and task |
| Ingress rule `SZ_PG_INGRESS`, procedure `SZ_REFRESH_PG_INGRESS`, daily task `SZ_PG_INGRESS_TASK`, policy `SZ_PG_POLICY` | admits only your region's Snowflake egress ranges from `SYSTEM$GET_SNOWFLAKE_EGRESS_IP_RANGES()`; never `0.0.0.0/0` |
| Postgres instance `SZ_PG` (PostgreSQL 17, JIT off; `SZ_PG_FAMILY`, `SZ_PG_STORAGE_GB`, `SZ_PG_HA` variables) | size and high availability. Postgres needs at least 8 GB: `STANDARD_L` (2 cores, 8 GB, 40,000 IOPS, 0.0712 credits/h on AWS) or larger; burstable families are not supported (CPU throttling, 100 GB storage cap); the script refuses a smaller family. The default `STANDARD_L` is the cheapest supported; for a large first load use `STANDARD_XL` or larger ([Sizing](use.md#sizing)) |
| Secrets `SZ_PG_ADMIN`, `SZ_PG_APP`, `SZ_PG_CA`, `SZ_LICENSE` | Snowflake generates both passwords (`RESET ACCESS`); the script copies them and the CA into secrets without displaying them |
| Egress rule `SZ_PG_EGRESS` with exactly `<PG_HOST>:5432` (`<PG_HOST>:<PG_PORT>` for your own database), and integration `SZ_PG_EAI` | the only egress the app gets |
| Procedures `SZ_PAUSE`, `SZ_UNPAUSE`, `SZ_AUTO_PAUSE`, log `SZ_PAUSE_LOG`, task `SZ_AUTO_PAUSE_TASK` (`SZ_AUTO_PAUSE`, `SZ_IDLE_PAUSE_MINUTES`, `SZ_AUTO_PAUSE_CHECK_MINUTES`, `SZ_PG_SHARED` variables) | pause to save money; `SZ_PG_SHARED = 'YES'` for a Postgres instance other workloads use: pausing then never suspends or resumes it, only the app's services and pool; auto-pause is on by default (checks every 10 minutes, pauses after 30 idle minutes, resumes when changes arrive); `SZ_AUTO_PAUSE = 'OFF'` creates no task ([Pause to save money](use.md#pause-to-save-money)) |
| `ALTER TABLE <db>.<schema>.<table> SET CHANGE_TRACKING = TRUE;` per source table (`SZ_SOURCE_TABLES`) | required: capture needs it, only the table's owner can set it, and `SZ_REGISTER_SOURCE` refuses a table without it (`-20208`) |

Exposure you accept: the egress ranges are shared by every Snowflake account in the
region. Protection is the generated password plus `verify-full` TLS. Private Link
(Business Critical) removes that exposure with one change to `SZ_PG_EGRESS`.

Verify: the script's last section prints `PG_HOST`, one egress entry, no `/0` ingress
prefix, `SZ_PG` `READY`, four secrets and the task `started`, the load sizing and the
`SZ_CONFIGURE` call to run after the install.

### Two installations in one account

Each installation needs its own application, its own infrastructure and its own Postgres:

1. Run the infrastructure script again with another prefix and application name, e.g.
   `SET SZ_PREFIX = 'SZ2';` and `SET SZ_APP = 'SZ_SNOWFLAKE_2';`. It creates `SZ2_INFRA_DB`
   (rules, secrets, procedures, tasks), the Postgres instance `SZ2_PG`, `SZ2_PG_POLICY` and
   `SZ2_PG_EAI`, and pauses only that installation.
2. Run the install script with `--app SZ_SNOWFLAKE_2 --infra-prefix SZ2`. The app names its
   compute pool and warehouse after itself (`SZ_SNOWFLAKE_2_POOL`, `SZ_SNOWFLAKE_2_WH`; an
   installation from before keeps `SZ_POOL` and `SZ_WH`).

Both apps come from the one application package `SZ_SNOWFLAKE_PKG`, so installing a new
release for one moves the other to it as well; the install script upgrades every app of the
package that a new patch reaches. A Postgres instance that other workloads use as well is not
suspended by pausing when you set `SZ_PG_SHARED = 'YES'` ([Pause to save money](use.md#pause-to-save-money)).

### Customizing the infrastructure script

Everything the script creates is yours to change. Whatever you change, the app needs exactly
these, under these names:

| The app needs | Notes |
|---|---|
| PostgreSQL 17 or later, reachable on `PG_HOST:PG_PORT` over TLS | setup refuses an older server; at least 8 GB of memory |
| Egress rule `SZ_PG_EGRESS` holding exactly `<PG_HOST>:<PG_PORT>`, in integration `SZ_PG_EAI` | the app's only egress |
| Secrets `SZ_PG_ADMIN` and `SZ_PG_APP` (`TYPE = PASSWORD`: username and password) | the admin login creates the database and roles (`CREATEDB`, `CREATEROLE`) and is read only by the setup job; the runtime login is a plain login the setup job grants DML to |
| Secret `SZ_PG_CA` (`TYPE = GENERIC_STRING`) | the PEM of the CA that signs the server certificate (Amazon RDS and Aurora: the region's certificate bundle from AWS) |
| Secret `SZ_LICENSE` (`TYPE = GENERIC_STRING`) | your Senzing license, base64; empty for the evaluation limit |

### Choosing a database

Snowflake Postgres is the default. Its I/O is capped by the compute family: 40,000 IOPS for
most families, 60,000 for `STANDARD_12XL`, 78,000 for `STANDARD_24XL` and `HIGHMEM_12XL` and
larger ([instance sizes](https://docs.snowflake.com/en/user-guide/snowflake-postgres/postgres-instance-sizes)).
A load that needs more I/O than that runs on a PostgreSQL you operate. Only PostgreSQL is
supported (not SQL Server or Azure SQL Hyperscale).

### Bring your own PostgreSQL

1. Set `SZ_PG_MODE = 'EXTERNAL'`, `SZ_PG_HOST` and `SZ_PG_PORT` at the top of the script. It
   then skips the Snowflake Postgres instance, its ingress rule, policy and refresh task,
   creates `SZ_PG_EGRESS` for exactly `SZ_PG_HOST:SZ_PG_PORT` and the integration, and
   prints the `CREATE SECRET` statements for `SZ_PG_ADMIN`, `SZ_PG_APP` and `SZ_PG_CA`
   instead of creating them.
2. Let the database accept TLS connections on its port from Snowflake's egress ranges
   (`SELECT SYSTEM$GET_SNOWFLAKE_EGRESS_IP_RANGES()`; they change, so refresh the allowlist),
   or connect privately (outbound private connectivity needs Business Critical; confirm with
   Snowflake that it covers container services on your cloud). Never allow `0.0.0.0/0`.
3. Run the printed `CREATE SECRET` statements yourself, with your logins filled in, in a
   worksheet of your own. Never paste a password into a chat or a shared script.
4. After the install, tell the app where the database is and how big it is, so the 8 GB
   minimum and the connection budget apply:

   ```sql
   CALL SZ_SNOWFLAKE.API.SZ_CONFIGURE({'PG_HOST': '<host>', 'PG_PORT': 5432, 'PG_DATABASE': '<database>',
     'PG_COMPUTE_FAMILY': 'EXTERNAL', 'PG_MEMORY_GIB': '<server memory, GiB>', 'PG_MAX_CONNECTIONS': '<its max_connections>'});
   ```

   (or the same with the install script's `--pg-host` and `--set`). Pausing an install with an
   external database suspends the app's services only; your database keeps running.

### Same region is required

Every record the resolvers load takes several round trips to the database, so latency
decides throughput. The compute pool runs in your Snowflake account's region: run the account
in the same cloud and region as the database (for example AWS `us-east-1` with Aurora in
`us-east-1`). `SELECT CURRENT_REGION();` shows the account's (e.g. `AWS_US_EAST_1`). Snowflake
does not let you choose the availability zone, so same-zone placement cannot be arranged.

<sub><b>THE APP</b></sub>

## 2. Install from the bundle

`sz-snowflake-install-<release>.sh` does everything from the downloaded files. Read it first
(`--dry-run` prints every step and runs nothing).

```bash
./sz-snowflake-install-<release>.sh <release> --pg-host <PG_HOST> --operator-role <role> [--role <role>] \
  [--accept-eula] [--platform linux/amd64|linux/arm64] [--assets <dir>] [--set <NAME>=<value> ...] \
  [--source <CODE>=<db.schema.mapping_view>:<db.schema.table>[,<db.schema.table>...][:<record id column>] ...]
```

`--role` is the role every Snowflake CLI call uses (default: the connection's role). It must be
able to create the package database, an application package and an application, for example
`ACCOUNTADMIN`; when it cannot, step 2 stops and says to re-run with `--role`.

`--source` names a data source, its mapping view and base tables (record id column
`RECORD_ID` unless given). The script binds them, registers the source after start and waits
until it is resolved ([register a source](use.md#register-a-source)), so one run ends with results.

It runs these steps, each printed before it runs:

1. **Verify** `SHA256SUMS` and the signature of every file present (the exact identity in the
   [README](../README.md#verify)), then unpack the bundle and check its own checksums.
2. **Create** the package database `SZ_SNOWFLAKE_PKG_DB`, an image repository `IMAGES` and a
   stage `APP_FILES`.
3. **Load and push the images.** The script uses the bundle for your compute pool's family:
   `sz-snowflake-<release>-linux-arm64.tar.gz` for the default (`GEN_ARM_G1_2`) or any
   `GEN_ARM_*`, `-linux-amd64` for an x86 family you set with `--set POOL_FAMILY=..`
   (`--platform` must agree); it stops and names the file when that bundle is not in
   `--assets`. Docker loads the bundle's one image archive and pushes each image to
   `SZ_SNOWFLAKE_PKG_DB.PKG.IMAGES` as `sz-snowflake-<role>:<release>` (a native app uses only
   images from a repository in its own account); `--loader skopeo` or `--loader crane`
   do the same without Docker. The login is a short-lived token from the Snowflake CLI.
   Pushing takes minutes per image (the first carries the shared ~290 MB layer): the script
   prints each image's start and finish with the seconds taken, and a line every 30 seconds
   while a push runs.
4. **Build the package and create the app.** A version or patch is a snapshot of the files
   when it is registered. The script records which files each patch came from (a marker
   under `@..APP_FILES/registered/`), so re-running it with the same bundle reuses the
   patch, and a rebuilt bundle of the same release gets a new patch labelled
   `<release>+<fingerprint>` instead of silently running the older one:

```sql
-- PUT the bundle's app/ files unchanged (and services/ likewise):
PUT file://<extracted>/app/* @SZ_SNOWFLAKE_PKG_DB.PKG.APP_FILES/<release>/ AUTO_COMPRESS = FALSE OVERWRITE = TRUE;
CREATE APPLICATION PACKAGE IF NOT EXISTS SZ_SNOWFLAKE_PKG DISTRIBUTION = INTERNAL;
-- first build of a Senzing version (ADD VERSION is refused: release channels are on):
ALTER APPLICATION PACKAGE SZ_SNOWFLAKE_PKG REGISTER VERSION V4_4_3
  USING '@SZ_SNOWFLAKE_PKG_DB.PKG.APP_FILES/<release>' LABEL = '<release>';
ALTER APPLICATION PACKAGE SZ_SNOWFLAKE_PKG MODIFY RELEASE CHANNEL DEFAULT ADD VERSION V4_4_3;
ALTER APPLICATION PACKAGE SZ_SNOWFLAKE_PKG MODIFY RELEASE CHANNEL DEFAULT
  SET DEFAULT RELEASE DIRECTIVE VERSION = V4_4_3 PATCH = <build>;
CREATE APPLICATION SZ_SNOWFLAKE FROM APPLICATION PACKAGE SZ_SNOWFLAKE_PKG;
GRANT CREATE COMPUTE POOL, BIND SERVICE ENDPOINT, CREATE WAREHOUSE, EXECUTE TASK, EXECUTE MANAGED TASK
  ON ACCOUNT TO APPLICATION SZ_SNOWFLAKE;
GRANT APPLICATION ROLE SZ_SNOWFLAKE.APP_ADMIN TO ROLE <operator_role>;
GRANT APPLICATION ROLE SZ_SNOWFLAKE.APP_USER TO ROLE <reader_role>;
-- the Postgres host and every --set in one call, all checked before any of them changes:
CALL SZ_SNOWFLAKE.API.SZ_CONFIGURE({'PG_HOST': '<PG_HOST>', 'PG_COMPUTE_FAMILY': 'STANDARD_L'});
CALL SZ_SNOWFLAKE.API.REGISTER_REFERENCE('PG_EAI', 'ADD',
  SYSTEM$REFERENCE('EXTERNAL ACCESS INTEGRATION', 'SZ_PG_EAI', 'PERSISTENT', 'USAGE'));
-- and the same for the four secrets with 'READ', and each --source view and table with 'SELECT'
```

`SZ_CONFIGURE` takes any setting of [Settings](use.md#settings) plus `PG_HOST`, `PG_PORT` and
`PG_DATABASE`; a bad value raises `-20023` listing every problem and changes nothing, and a
configuration that does not fit a pool node or the Postgres connection budget raises `-20024`
([Sizing](use.md#sizing)). Pass `--set PG_COMPUTE_FAMILY=<your SZ_PG_FAMILY>` (the infrastructure
script prints the `SZ_CONFIGURE` call with it). It
returns the references still unbound: those only you can bind, with `REGISTER_REFERENCE`
(an app cannot bind a reference itself).

The app creates only its own objects (pool `<APP>_POOL`, warehouse `<APP>_WH`, tables, tasks,
services). Next the script prints the Senzing EULA link (step 3 below). With `--accept-eula`
it then runs the acceptance `CALL` for you; without it, it prints that `CALL` and stops
before setup until the EULA is accepted. It ends by running setup and start (step 5 below), registers each `--source` and
waits for `RESOLVE_STATE = CAUGHT_UP` (`--resolve-wait`, default 1800 s), and exits non-zero
unless `SZ_HEALTH.OVERALL` reads `OK`. Verify: `SHOW REFERENCES IN APPLICATION SZ_SNOWFLAKE` lists
the five bindings.

<sub><b>LICENSE TERMS</b></sub>

## 3. Accept the Senzing EULA

The first step once the app exists. Read the
[Senzing End User License Agreement](https://senzing.com/end-user-license-agreement/), then
accept it as the role that created the app or one holding `APP_ADMIN`:

```sql
CALL SZ_SNOWFLAKE.API.SZ_ACCEPT_EULA('I_ACCEPT_THE_SENZING_EULA');
```

Only that exact value is accepted; anything else raises `-20109` and names the agreement.
The app records the EULA version, its URL, the time, the user who called, and the app
version and label in `SZ_SNOWFLAKE.SZ.SZ_EULA_ACCEPTANCE` (`APP_ADMIN` can read it).
`SZ_SETUP` and `SZ_START` refuse with `-20109` until it is accepted, and again after an
upgrade to a release that carries a new EULA version. The install script does this step
for you with `--accept-eula`. Verify: `SELECT EULA_VERSION, EULA_ACCEPTED_AT,
EULA_ACCEPTED_BY FROM SZ_SNOWFLAKE.API.SZ_HEALTH` shows the acceptance.

<sub><b>OPTIONAL</b></sub>

## 4. Set the license secret

Run interactively, never committed:
`ALTER SECRET SZ_LICENSE SET SECRET_STRING = '<base64>'`. It stays yours: the app has
`READ`, logs only its expiry date and record limit, and never sends it anywhere. If the
services are already running, `CALL SZ_SNOWFLAKE.API.SZ_RELOAD_SECRETS()` restarts them so
they read it (secrets are read once at start). The same applies to a rotated Postgres
password or a new CA (the infra script's `ROTATE` section).

<sub><b>FIRST RUN</b></sub>

## 5. Run setup and start

```sql
CALL SZ_SNOWFLAKE.API.SZ_SETUP('install');
CALL SZ_SNOWFLAKE.API.SZ_START();
SELECT OVERALL FROM SZ_SNOWFLAKE.API.SZ_HEALTH;   -- OK
```

Into a `PG_DATABASE` that already holds an earlier install's records, `SZ_SETUP('install')`
keeps them and warns about those of data sources this app has not registered, per data source (`existing records:` in its result's `warnings`;
`SZ_HEALTH` `EXISTING_RECORDS`). To start clean use a new `PG_DATABASE`, or
`SZ_UNINSTALL('<PG_DATABASE>')` first ([teardown](use.md#teardown)).

`SZ_SETUP` requires the accepted EULA (step 3), the five bound references (`PG_EAI`, `PG_ADMIN_SECRET`,
`PG_APP_SECRET`, `PG_CA_SECRET`, `LICENSE_SECRET`) and runs the setup job: it creates the
Postgres side and, only when there is none, the Senzing default configuration. Re-running
changes nothing. The call waits at most `START_WAIT_SECS` (default 900 s); a pool that
cannot schedule a node ends the call with the job's own status message instead of
hanging, and a failed job raises `-20101` with `reason=.. error=..` first. Verify: the
newest `SZ_SETUP_LOG` row has `EXIT_CODE = 0`.

The call shows nothing until it returns (usually 2 to 5 minutes). To watch it, run in a
second worksheet:

```sql
SELECT SETUP_PHASE, SETUP_RUNNING_SECS FROM SZ_SNOWFLAKE.API.SZ_HEALTH;
```

`SETUP_PHASE` reads `waiting_for_job_container` while the pool brings up a node and pulls
the image, then the job's phase (`pg_connect`, `provision`, `senzing_schema`,
`sz_snowflake_schema`, `engine_bootstrap`), and `NULL` once the run ended. The result's
`timing` splits where the time went: `until_job_started_secs` (node and image),
`in_job_secs`, and `phases` with seconds each (the engine bootstrap also by part:
`default_config`, `engine_init`, `data_sources`, `license_and_facts`).

`SZ_START` creates the pool, the warehouse, the tasks, both services (`RESOLVER_INSTANCES`
default 2, `REPLICATOR_INSTANCES` default 1) and the service functions, waits for the
services and raises `-20107` with both statuses when they are not `READY`. Either way it
refreshes `SZ_HEALTH` before returning, so `OVERALL` is current right after the call. The
install script exits non-zero unless `OVERALL` reads `OK`.

<sub><b>CORD DATA</b></sub>

## No data of your own? Load the CORD data

`sz-snowflake-cord-data.tar.gz` is the CORD data for the Senzing Snowflake preview: Senzing's
official [CORD](https://senzing.com/senzing-ready-data-collections-cord/) data, from its Las Vegas collection, reshaped into normalized source
tables for six source systems (about 200,000 records). The original JSONL is on the
[CORD page](https://senzing.com/senzing-ready-data-collections-cord/). Download it with the release and verify it like the other files
([README](../README.md#verify)), then:

```bash
tar -xzf sz-snowflake-cord-data.tar.gz   # tar is built into macOS, Linux and Windows 10+
cd sz-snowflake-cord-data
cat README.md load.sql            # what it holds, and what the script does
snow sql -c <connection> -f load.sql
```

`load.sql` creates the database `SZ_CORD_DATA` (change the `SET` at its top for another
name), one schema per source system, every table with `CHANGE_TRACKING = TRUE`, and a
stage `PUBLIC.CORD_STAGE`; it uploads the CSV files with `PUT` (so run it from the extracted
directory) and loads them with `COPY INTO`. Re-running it is safe. Its last query lists
every table's loaded and expected row counts; they must be equal. Without a client that
can `PUT`, upload each source directory to the stage in Snowsight and run the other
statements.

The tables are ordinary business tables, not Senzing records: map each source system to
Senzing before you register it (next).

Next: [register a source](use.md#register-a-source). If a step fails:
[troubleshooting](troubleshooting.md).
