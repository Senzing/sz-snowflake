# Install

**From a signed release to a running app, in your own Snowflake account.** You are both
the provider and the consumer of the app; everything happens in your account. Start with
the [README](../README.md): prerequisites and how to verify the release files.

Download one release's files into a directory and run the steps from there. Replace
`<release>` with the release, for example `4.4.3-1`.

## 1. Run the infrastructure script

`sz-snowflake-infra-<release>.sql`: you run it, you own everything it creates, and you can
change any of it later. **Read every statement before you run it.** It is re-runnable,
never prints a secret, and ends with a verification query.

| It creates | Review |
|---|---|
| `SZ_INFRA_DB.SZ_INFRA` | home for your rules, secrets, procedure and task |
| Ingress rule `SZ_PG_INGRESS`, procedure `SZ_REFRESH_PG_INGRESS`, daily task `SZ_PG_INGRESS_TASK`, policy `SZ_PG_POLICY` | admits only your region's Snowflake egress ranges from `SYSTEM$GET_SNOWFLAKE_EGRESS_IP_RANGES()`; never `0.0.0.0/0` |
| Postgres instance `SZ_PG` (PostgreSQL 17; `SZ_PG_FAMILY`, `SZ_PG_STORAGE_GB`, `SZ_PG_HA` variables) | size and high availability |
| Secrets `SZ_PG_ADMIN`, `SZ_PG_APP`, `SZ_PG_CA`, `SZ_LICENSE` | Snowflake generates both passwords (`RESET ACCESS`); the script copies them and the CA into secrets without displaying them |
| Egress rule `SZ_PG_EGRESS` with exactly `<PG_HOST>:5432`, and integration `SZ_PG_EAI` | the only egress the app gets |
| `ALTER TABLE <db>.<schema>.<table> SET CHANGE_TRACKING = TRUE` per source table | capture needs it and the app cannot do it |

Exposure you accept: the egress ranges are shared by every Snowflake account in the
region. Protection is the generated password plus `verify-full` TLS. Private Link
(Business Critical) removes that exposure with one change to `SZ_PG_EGRESS`.

Verify: the script's last section prints `PG_HOST`, one egress entry, no `/0` ingress
prefix, `SZ_PG` `READY`, four secrets and the task `started`.

## 2. Install from the bundle

`sz-snowflake-install-<release>.sh` does everything from the downloaded files. Read it first
(`--dry-run` prints every step and runs nothing).

```bash
./sz-snowflake-install-<release>.sh <release> --pg-host <PG_HOST> --operator-role <role> \
  [--accept-eula] [--platform linux/amd64|linux/arm64] [--assets <dir>] [--source-table <db.schema.table> ...]
```

It runs these steps, each printed before it runs:

1. **Verify** `SHA256SUMS` and the signature of every file present (the exact identity in the
   [README](../README.md#verify)), then unpack the bundle and check its own checksums.
2. **Create** the package database `SZ_SNOWFLAKE_PKG_DB`, an image repository `IMAGES` and a
   stage `APP_FILES`.
3. **Load and push the images.** The bundle holds the images of both architectures; only one
   is pushed, the one for your compute pool: `--platform`, or `--set POOL_FAMILY=GEN_ARM_*`
   means `linux/arm64`, otherwise `linux/amd64`. Docker loads each archive and pushes it to
   `SZ_SNOWFLAKE_PKG_DB.PKG.IMAGES` as `sz-snowflake-<role>:<release>` (a native app uses only
   images from a repository in its own account); `--loader skopeo` or `--loader crane`
   do the same without Docker. The login is a short-lived token from the Snowflake CLI.
4. **Build the package and create the app:**

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
CALL SZ_SNOWFLAKE.API.SZ_CONFIGURE_PG('<PG_HOST>');
CALL SZ_SNOWFLAKE.API.REGISTER_REFERENCE('PG_EAI', 'ADD',
  SYSTEM$REFERENCE('EXTERNAL ACCESS INTEGRATION', 'SZ_PG_EAI', 'PERSISTENT', 'USAGE'));
-- and the same for the four secrets with 'READ'
```

The app creates only its own objects (pool `SZ_POOL`, warehouse `SZ_WH`, tables, tasks,
services). Next the script prints the Senzing EULA link (step 3 below). With `--accept-eula`
it then runs the acceptance `CALL` for you; without it, it prints that `CALL` and stops
before setup until the EULA is accepted. It ends by running setup and start (step 5 below)
and exits non-zero unless `SZ_HEALTH.OVERALL` reads `OK`. Verify: `SHOW REFERENCES IN APPLICATION SZ_SNOWFLAKE` lists
the five bindings.

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

## 4. Set the license secret

Run interactively, never committed:
`ALTER SECRET SZ_LICENSE SET SECRET_STRING = '<base64>'`. It stays yours: the app has
`READ`, logs only its expiry date and record limit, and never sends it anywhere. If the
services are already running, `CALL SZ_SNOWFLAKE.API.SZ_RELOAD_SECRETS()` restarts them so
they read it (secrets are read once at start). The same applies to a rotated Postgres
password or a new CA (the infra script's `ROTATE` section).

## 5. Run setup and start

```sql
CALL SZ_SNOWFLAKE.API.SZ_SETUP('install');
CALL SZ_SNOWFLAKE.API.SZ_START();
SELECT OVERALL FROM SZ_SNOWFLAKE.API.SZ_HEALTH;   -- OK
```

`SZ_SETUP` requires the accepted EULA (step 3), the five bound references (`PG_EAI`, `PG_ADMIN_SECRET`,
`PG_APP_SECRET`, `PG_CA_SECRET`, `LICENSE_SECRET`) and runs the setup job: it creates the
Postgres side and, only when there is none, the Senzing default configuration. Re-running
changes nothing. The call waits at most `START_WAIT_SECS` (default 900 s); a pool that
cannot schedule a node ends the call with the job's own status message instead of
hanging, and a failed job raises `-20101` with `reason=.. error=..` first. Verify: the
newest `SZ_SETUP_LOG` row has `EXIT_CODE = 0`.

`SZ_START` creates the pool, the warehouse, the tasks, both services (`RESOLVER_INSTANCES`
default 2, `REPLICATOR_INSTANCES` default 1) and the service functions, waits for the
services and raises `-20107` with both statuses when they are not `READY`. Either way it
refreshes `SZ_HEALTH` before returning, so `OVERALL` is current right after the call. The
install script exits non-zero unless `OVERALL` reads `OK`.

Next: [register a source](use.md#register-a-source). If a step fails:
[troubleshooting](troubleshooting.md).
