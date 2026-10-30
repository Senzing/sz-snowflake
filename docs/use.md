# Use

Day-to-day operation of an installed app. Procedures are in `SZ_SNOWFLAKE.API`; the
roles are `APP_ADMIN` (operates) and `APP_USER` (reads health and the results).

## Register a source

You need a mapping view with `DATA_SOURCE`, `RECORD_ID` (VARCHAR) and `JSON_DOC`
(OBJECT/VARIANT) in the Senzing entity specification. An AI assistant can draft it with the
Senzing MCP `mapping_workflow`. Bind the view and its base tables as references, then:

```sql
-- each ADD returns the alias the next call needs
CALL SZ_SNOWFLAKE.API.REGISTER_REFERENCE('SOURCE_VIEWS', 'ADD',
  SYSTEM$REFERENCE('VIEW', '<db>.<schema>.<mapping_view>', 'PERSISTENT', 'SELECT'));
CALL SZ_SNOWFLAKE.API.REGISTER_REFERENCE('SOURCE_TABLES', 'ADD',
  SYSTEM$REFERENCE('TABLE', '<db>.<schema>.<base_table>', 'PERSISTENT', 'SELECT'));
CALL SZ_SNOWFLAKE.API.SZ_REGISTER_SOURCE('<CODE>', '<view_alias>',
  [{'table_alias': '<table_alias>', 'record_id_column': '<RECORD_ID column of that table>'}]);
```

`<CODE>` matches `^[A-Z0-9_-]{1,64}$` and equals the view's `DATA_SOURCE`; give one entry
per base table in exactly the `{"table_alias", "record_id_column"}` shape (a plain array of
aliases is refused with `-20204`, naming the shape). Every argument is checked before
anything is created, so a bad second table never leaves a half-registered source.

**Change tracking.** Capture reads changes through a stream, so each base table needs
`CHANGE_TRACKING = TRUE`, and only the table's owner can set it (the infrastructure script
does it for the tables you list). A table without it: the call returns
`ALTER TABLE <table> SET CHANGE_TRACKING = TRUE` for its owner to run, naming the alias
(`SHOW REFERENCES IN APPLICATION SZ_SNOWFLAKE` maps the alias to the table), and leaves the
source `FAILED` until it is registered again.

## Watch it resolve

| Check | Expect |
|---|---|
| `SELECT PENDING_KEYS, OVERALL FROM SZ_SNOWFLAKE.API.SZ_HEALTH` | pending keys fall to 0 |
| `CALL SZ_SNOWFLAKE.API.SZ_FLUSH()` | returns when everything captured so far is applied |
| `SELECT * FROM SZ_SNOWFLAKE.SZ.ENTITY_RECORD LIMIT 10` | each record has its `ENTITY_ID` |
| Edit a source row | its `ENTITY_ID` updates after the next cut (`CUT_MAX_AGE_SECS`, default 120 s), resolve, the replicator's claim wait (`CLAIM_MAX_WAIT_SECS`, default 60 s) and apply: up to about 4 minutes. The cut opens at once when `BATCH_MIN_KEYS` (20,000) fresh keys are waiting, so a first load or a backlog never waits |
| `CALL SZ_SNOWFLAKE.API.SZ_VALIDATE()` | `SZ_VALIDATION.MISMATCHED = 0` |
| `SELECT SZ_SNOWFLAKE.SZ.SZ_STATUS()` | license `expire_date` and `record_limit`, instance states |

The results are `ENTITY`, `ENTITY_RECORD` (the crosswalk from your records to entities) and
`RELATIONSHIP` in schema `SZ`.

## Settings

`CALL SZ_SNOWFLAKE.API.SZ_SET_CONFIG('<NAME>', '<value>')`; `SELECT NAME, VALUE FROM
SZ_SNOWFLAKE.SZ.SZ_CONFIG WHERE KIND = 'SETTING'` lists them. Changes to a pipeline setting
(first group) apply at the next task run; the rest at the next `SZ_START` or `SZ_UPGRADE`.

| Setting | Default | Meaning |
|---|---|---|
| `CUT_MAX_AGE_SECS` | 120 | the longest captured keys wait before a batch is cut; lower it for an interactive demo |
| `BATCH_MIN_KEYS` / `BATCH_MAX_KEYS` | 20,000 / 50,000 | a batch is cut early at the minimum and never exceeds the maximum |
| `MAX_READY_BATCHES` | 20 | batches cut ahead of the resolvers |
| `SWEEP_EVERY_CUTS` | 20 | every n-th cut also sweeps for keys capture missed |
| `TIMEOUT_MAX_ATTEMPTS` | 3 | attempts before a failing entity or redo record counts as dead |
| `RETENTION_DAYS` | 7 | how long finished batches are kept |
| `BACKLOG_KEYS`, `BACKLOG_WAREHOUSE_SIZE` | 1,000,000, `MEDIUM` | a backlog this large scales `SZ_WH` up from `XSMALL` |
| `APPLY_SLOW_SECS` | 60 | an apply slower than this scales `SZ_WH` up |
| `CLAIM_MAX_WAIT_SECS` | 60 | see below (1..900) |
| `POOL_FAMILY`, `POOL_MAX_NODES` | `GEN_X64_G2_8`, 3 | the compute pool; use an ARM family for `linux/arm64` images |
| `RESOLVER_INSTANCES`, `RESOLVER_CPU`, `RESOLVER_MEMORY`, `RESOLVER_THREADS` | 2, 6, `28Gi`, automatic | resolver sizing |
| `REPLICATOR_INSTANCES`, `REPLICATOR_CPU`, `REPLICATOR_MEMORY` | 1, 2, `8Gi` | replicator sizing |
| `START_WAIT_SECS` | 900 | how long `SZ_SETUP` and `SZ_START` wait |
| `PG_INSECURE_TLS` | 0 | `1` accepts any server certificate; `SZ_HEALTH` reads `FAIL` until it is `0`. Never for production |

**`CLAIM_MAX_WAIT_SECS` and latency.** The replicator does not apply every resolved entity
at once: it claims a batch when 50,000 ids are queued or when the oldest queued id has
waited `CLAIM_MAX_WAIT_SECS`, whichever comes first. Each apply scans the replica, so
fewer, larger claims are cheaper per id. A trickle of changes therefore reaches the replica
at most `CLAIM_MAX_WAIT_SECS` after it is resolved. Shorten it (`SZ_SET_CONFIG(
'CLAIM_MAX_WAIT_SECS', '20')`) for an interactive demo. For a large load, raise it (at most
900) when `SZ_APPLY` is the bottleneck: `SELECT INSTANCE, APPLY_SECS, ENTITIES_LIVE FROM
SZ_SNOWFLAKE.SZ.SZ_APPLY_LOG ORDER BY APPLIED_AT DESC LIMIT 20` showing many applies of a
few hundred entities that each take tens of seconds means the claims are too small.

## Upgrade

A later build of the same Senzing version (`4.4.3-1` to `4.4.3-2`): download and verify the
new release, then run its install script with `--upgrade` (it pushes the new images, `PUT`s
the new app files and registers the patch). By hand, after the files are in the stage:

```sql
ALTER APPLICATION PACKAGE SZ_SNOWFLAKE_PKG ADD PATCH 2 FOR VERSION V4_4_3
  USING '@SZ_SNOWFLAKE_PKG_DB.PKG.APP_FILES/4.4.3-2' LABEL = '4.4.3-2';
ALTER APPLICATION PACKAGE SZ_SNOWFLAKE_PKG MODIFY RELEASE CHANNEL DEFAULT
  SET DEFAULT RELEASE DIRECTIVE VERSION = V4_4_3 PATCH = 2;
CALL SZ_SNOWFLAKE.API.SZ_PREPARE_UPGRADE();   -- optional drain
ALTER APPLICATION SZ_SNOWFLAKE UPGRADE;
CALL SZ_SNOWFLAKE.API.SZ_UPGRADE();
```

A new Senzing
version (`4.4.4-1`) is `REGISTER VERSION V4_4_4 .. LABEL = '4.4.4-1'`, added to the
`DEFAULT` channel, then the same directive, upgrade and `SZ_UPGRADE`; deregister `V4_4_3`
once no app reports it (a channel holds two versions). Verify: `SZ_HEALTH.UPGRADE_PENDING`
clears and `OVERALL` is `OK`; no version stays `FINALIZING` in `SHOW VERSIONS IN APPLICATION
PACKAGE SZ_SNOWFLAKE_PKG`. `SZ_UPGRADE` stops at the first failing step and resumes there
when you call it again.

A release that carries a new Senzing EULA version needs a new acceptance: `SZ_UPGRADE`
returns `FAILED` with `-20109` until `CALL SZ_SNOWFLAKE.API.SZ_ACCEPT_EULA('I_ACCEPT_THE_SENZING_EULA')`
runs, then resumes when called again. The install script checks this after `ALTER APPLICATION
.. UPGRADE`: it stops with the `CALL` to run, or runs it with `--accept-eula`.

## Teardown

```sql
CALL SZ_SNOWFLAKE.API.SZ_STOP();
DROP APPLICATION IF EXISTS SZ_SNOWFLAKE CASCADE;
DROP APPLICATION PACKAGE IF EXISTS SZ_SNOWFLAKE_PKG;
DROP DATABASE IF EXISTS SZ_SNOWFLAKE_PKG_DB;
```

Then the infrastructure script's `TEARDOWN` section (`SET SZ_INCLUDE_POSTGRES = 'NO'` keeps
the Postgres instance). Verify: `SHOW APPLICATIONS`, `SHOW APPLICATION PACKAGES`, `SHOW
COMPUTE POOLS`, `SHOW WAREHOUSES LIKE 'SZ_WH'`, `SHOW POSTGRES INSTANCES`, `SHOW NETWORK
POLICIES` and `SHOW EXTERNAL ACCESS INTEGRATIONS` list nothing of ours.
