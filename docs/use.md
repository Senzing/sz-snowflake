[sz-snowflake](../README.md) / Use

# Use

Day-to-day operation of an installed app. Procedures are in `SZ_SNOWFLAKE.API`; the
roles are `APP_ADMIN` (operates) and `APP_USER` (reads health and the results).

## Register a source

You need a mapping view with `DATA_SOURCE`, `RECORD_ID` (VARCHAR) and `RECORD_JSON`
(OBJECT/VARIANT) in the SENZING® entity specification. An AI assistant can draft it with
`mapping_workflow` from the Senzing Model Context Protocol (MCP) server. Bind the view and its base tables as references (only you
can bind a reference), then register the source by name:

```sql
CALL SZ_SNOWFLAKE.API.REGISTER_REFERENCE('SOURCE_VIEWS', 'ADD',
  SYSTEM$REFERENCE('VIEW', '<db>.<schema>.<mapping_view>', 'PERSISTENT', 'SELECT'));
CALL SZ_SNOWFLAKE.API.REGISTER_REFERENCE('SOURCE_TABLES', 'ADD',
  SYSTEM$REFERENCE('TABLE', '<db>.<schema>.<base_table>', 'PERSISTENT', 'SELECT'));
CALL SZ_SNOWFLAKE.API.SZ_REGISTER_SOURCE('<CODE>', '<db>.<schema>.<mapping_view>',
  [{'table': '<db>.<schema>.<base_table>', 'record_id_column': '<RECORD_ID column of that table>'}]);
```

The app finds the bindings by name itself; no `SHOW REFERENCES` lookup is needed. A table
entry may also be the plain name (`['<db>.<schema>.<base_table>']`, record id column
`RECORD_ID`), and the reference aliases `REGISTER_REFERENCE` returns are still accepted in
place of names (`'table_alias'` in an entry). A name with no binding is refused (`-20203`
for the view, `-20204` for a table) with the `REGISTER_REFERENCE` call to run.
`<CODE>` matches `^[A-Z0-9_-]{1,64}$` and equals the view's `DATA_SOURCE`; give one entry
per base table. Every argument is checked before anything is created, so a bad second
table never leaves a half-registered source. The install script does all of this with
`--source <CODE>=<view>:<table>[=<column>][,<table>[=<column>]...][:<record id column>]`;
`<table>=<column>` gives that table its own record id column (a child table's foreign key).

**Tables shared across sources.** A mapping view may read any table it can see, including
one registered under another source (a contacts view joining the CRM's `ACCOUNTS` for the
employer). Only the tables listed for a source drive its capture: a changed row of a listed
table re-resolves the record whose id is in that table's record id column. So:

- A table that holds the source's record id (the main table, or a child table with a
  foreign key to it) is listed with that column as its `record_id_column`.
- A table the view only *looks up* (contacts read their employer's `ACCOUNTS` row, which
  holds no contact id) is listed with a `via`: the column of the changed row, and the
  source table and column that point at it. A change to the looked-up row re-resolves
  every record that points at it, before and after the change:

  ```sql
  CALL SZ_SNOWFLAKE.API.SZ_REGISTER_SOURCE('CRM_CONTACT', 'CRM.PUBLIC.CONTACT_MAPPED', [
    {'table': 'CRM.PUBLIC.CONTACTS', 'record_id_column': 'CONTACT_ID'},
    {'table': 'CRM.PUBLIC.ACCOUNTS', 'key_column': 'ACCOUNT_ID',
     'via': {'table': 'CRM.PUBLIC.CONTACTS', 'key_column': 'ACCOUNT_ID', 'record_id_column': 'CONTACT_ID'}}]);
  ```

  The `via` table must be one of the source's own tables (listed with its
  `record_id_column`); the looked-up table needs change tracking like any other. The
  install script's form is
  `--source-via CRM_CONTACT=CRM.PUBLIC.ACCOUNTS.ACCOUNT_ID:CRM.PUBLIC.CONTACTS.ACCOUNT_ID.CONTACT_ID`.
- Each source gets its own stream on a table, so the same table under two sources is fine
  (`ACCOUNTS` as `CRM_ACCOUNT`'s main table and as a `via` table of `CRM_CONTACT`).

**The CORD data.** The [Collections Of Relatable Data (CORD)](install.md#no-data-of-your-own-load-the-cord-data)
(the official Senzing [CORD](https://senzing.com/senzing-ready-data-collections-cord/) data, from its Las Vegas collection, reshaped into
normalized source tables) must be mapped first: no table is in the Senzing entity
specification. Register one source per source system (`CRM`, `PROVIDER_REGISTRY` and so on;
a system that holds two kinds of record, such as the CRM's accounts and contacts, can be
two). A source's mapping view joins its main table to the child tables (addresses, phones,
identifiers); list every table the view reads as a base table, each with the column that
holds the record id (a child table's foreign key to the main table). The tables already
have change tracking.

**Change tracking is required.** Capture reads changes through a stream, so every base
table needs change tracking, and only the table's owner can turn it on (the infrastructure
script does it for the tables in `SZ_SOURCE_TABLES`):

```sql
ALTER TABLE <db>.<schema>.<table> SET CHANGE_TRACKING = TRUE;
```

`SZ_REGISTER_SOURCE` checks every table first and refuses (`-20208`, nothing registered)
when one lacks it, naming the exact statement. Run it as the owner, then call
`SZ_REGISTER_SOURCE` again with the same arguments. The same call repairs a source that
fails later (change tracking turned off, a stream gone stale): `RESOLVE_STATE` reads
`SOURCES_FAILED` and `SOURCE_ERRORS` says what to run.

**An earlier install's data.** `SZ_SETUP('install')` into a `PG_DATABASE` that already holds
Senzing records keeps them and resolves your new records with them. Records of data sources
this app has not registered (an earlier install's) are reported in its result and in
`SZ_HEALTH` (`EXISTING_RECORDS`, `LAST_SETUP_WARNINGS`), per data source; the records of your
own registered sources are not, so re-running `SZ_SETUP` on your own install stays quiet.
Remove one source's with `SZ_PURGE_SOURCE` (below). To
start clean, drop that database first with `CALL SZ_SNOWFLAKE.API.SZ_UNINSTALL('<PG_DATABASE>')`
(see [Teardown](#teardown)) or configure a new `PG_DATABASE` before `SZ_SETUP`.

## Watch it resolve

```sql
SELECT RESOLVE_STATE, OVERALL, LAST_CAPTURE_AT, LAST_APPLY_AT,
  (SELECT COUNT(*) FROM SZ_SNOWFLAKE.SZ.ENTITY_RECORD) AS RESOLVED_RECORDS
FROM SZ_SNOWFLAKE.API.SZ_HEALTH;
```

`RESOLVE_STATE` is the done signal: `NO_SOURCES`, `SOURCES_FAILED` (a source's capture
failed: never done until it is fixed, `SOURCE_ERRORS` says how) → `WAITING_FOR_CAPTURE` (registered or
changed rows not yet captured and cut into a batch) → `RESOLVING` (batches in the resolver,
or results not yet written back) → `CAUGHT_UP` (everything captured so far is resolved and
in `ENTITY_RECORD`). Do not use `PENDING_KEYS` for this: it is a snapshot taken every 10
minutes and can read 0 before anything was captured.

| Check | Expect |
|---|---|
| `SELECT RESOLVE_STATE FROM SZ_SNOWFLAKE.API.SZ_HEALTH` | `CAUGHT_UP` |
| `CALL SZ_SNOWFLAKE.API.SZ_FLUSH()` | returns when everything captured so far is applied |
| `SELECT * FROM SZ_SNOWFLAKE.SZ.ENTITY_RECORD LIMIT 10` | each record has its `ENTITY_ID` |
| Edit a source row | its `ENTITY_ID` updates after the next cut (`CUT_MAX_AGE_SECS`, default 120 s), resolve, the replicator's claim wait (`CLAIM_MAX_WAIT_SECS`, default 60 s) and apply: up to about 4 minutes. The cut opens at once when `BATCH_MIN_KEYS` (1,000) fresh keys are waiting, so a first load or a backlog never waits |
| `CALL SZ_SNOWFLAKE.API.SZ_VALIDATE()` | `SZ_VALIDATION.MISMATCHED = 0` |
| `SELECT SZ_SNOWFLAKE.SZ.SZ_STATUS()` | license `expire_date` and `record_limit`, instance states |

The results are `ENTITY`, `ENTITY_RECORD` (the crosswalk from your records to entities) and
`RELATIONSHIP` in schema `SZ`.

To show a record's name, address or phone next to its entity, join the crosswalk to your
own mapping view on `DATA_SOURCE` and `RECORD_ID`: you read only what your role may read.
For example, every name in entity 1234 from source `CUSTOMERS`:

```sql
SELECT er.ENTITY_ID, er.RECORD_ID,
       COALESCE(f.VALUE:NAME_FULL::VARCHAR, f.VALUE:NAME_ORG::VARCHAR,
                ARRAY_TO_STRING(ARRAY_CONSTRUCT_COMPACT(f.VALUE:NAME_FIRST::VARCHAR,
                  f.VALUE:NAME_MIDDLE::VARCHAR, f.VALUE:NAME_LAST::VARCHAR), ' ')) AS NAME
FROM SZ_SNOWFLAKE.SZ.ENTITY_RECORD er
JOIN <db>.<schema>.CUSTOMERS_MAPPED m ON m.DATA_SOURCE = er.DATA_SOURCE AND m.RECORD_ID = er.RECORD_ID
JOIN TABLE(FLATTEN(INPUT => m.RECORD_JSON:FEATURES)) f
WHERE er.ENTITY_ID = 1234
  AND (f.VALUE:NAME_FULL IS NOT NULL OR f.VALUE:NAME_ORG IS NOT NULL OR f.VALUE:NAME_LAST IS NOT NULL);
```

`UNION ALL` one such query per source for all of them. Two Snowflake details: use
`JOIN TABLE(FLATTEN(..))` (a comma `LATERAL FLATTEN` followed by another `JOIN .. ON` that
names the first table fails with `invalid identifier`), and join name parts with
`ARRAY_TO_STRING(ARRAY_CONSTRUCT_COMPACT(..))` (`CONCAT_WS` is NULL when any part is, which
blanks a name without a middle name).

## Settings

`CALL SZ_SNOWFLAKE.API.SZ_SET_CONFIG('<NAME>', '<value>')`, or several at once with
`CALL SZ_SNOWFLAKE.API.SZ_CONFIGURE({'<NAME>': '<value>', ..})` (every value checked before
any changes; `-20023` lists the problems); `SELECT NAME, VALUE FROM
SZ_SNOWFLAKE.SZ.SZ_CONFIG WHERE KIND = 'SETTING'` lists them. Changes to a pipeline setting
(first group) apply at the next task run; the rest at the next `SZ_START` or `SZ_UPGRADE`.

| Setting | Default | Meaning |
|---|---|---|
| `CUT_MAX_AGE_SECS` | 120 | the longest captured keys wait before a batch is cut; lower it for an interactive demo |
| `BATCH_MIN_KEYS` / `BATCH_MAX_KEYS` | 1,000 / 5,000 | a batch is cut early at the minimum and never exceeds the maximum; small batches spread over the resolvers and a restart re-resolves less |
| `MAX_READY_BATCHES` | 20 | batches cut ahead of the resolvers |
| `SWEEP_EVERY_CUTS` | 20 | every n-th cut also sweeps for keys capture missed |
| `TIMEOUT_MAX_ATTEMPTS` | 3 | attempts before a failing entity or redo record counts as dead |
| `RETENTION_DAYS` | 7 | how long finished batches are kept |
| `BACKLOG_KEYS`, `BACKLOG_WAREHOUSE_SIZE` | 1,000,000, `MEDIUM` | a backlog this large scales `<APP>_WH` up from `XSMALL` |
| `APPLY_SLOW_SECS` | 60 | an apply slower than this scales `<APP>_WH` up |
| `CLAIM_MAX_WAIT_SECS` | 60 | see below (1..900) |
| `POOL_FAMILY`, `POOL_MAX_NODES` | `GEN_ARM_G1_2`, empty | the compute pool: the cheapest nodes with more than 4 GB (1 vCPU, 6 GiB; `linux/arm64` images), one container each; empty `POOL_MAX_NODES` is a node for each resolver `RESOLVER_MAX_INSTANCES` allows, the replicator and the setup job. The pool starts with a node for each container the services start with (`RESOLVER_INSTANCES` plus the replicator), so a start or resume brings them up together; any family works (an x86 one takes the `linux/amd64` images). A new family takes effect at `SZ_START`, which stops the services and recreates the pool |
| `RESOLVER_INSTANCES`, `RESOLVER_MAX_INSTANCES` | 1, empty | the resolvers autoscale on CPU between the two. Empty maximum: as many as Postgres can feed, 2 resolver CPUs per core of `PG_COMPUTE_FAMILY` (4 on `STANDARD_L`, 8 on `STANDARD_XL`; 4 when the family is not set or `EXTERNAL`). A number caps it there (see [Sizing](#sizing)) |
| `RESOLVER_CPU`, `RESOLVER_THREADS`, `RESOLVER_MEMORY` | 1, empty, empty | per resolver; empty threads are 6 x the CPU (at least 2: about 20% of them, at least 1, re-evaluate pending work, the rest load records; 6 threads are 5 + 1), empty memory is 4 GiB + 0.5 GiB per thread, at most what one `POOL_FAMILY` node can give a container, at least 4 GiB |
| `REPLICATOR_INSTANCES`, `REPLICATOR_CPU`, `REPLICATOR_THREADS`, `REPLICATOR_MEMORY` | 1, 1, empty, empty | the replicator, sized the same way |
| `PG_COMPUTE_FAMILY`, `PG_MAX_CONNECTIONS`, `PG_MEMORY_GIB` | empty, empty, empty | your Snowflake Postgres instance's `COMPUTE_FAMILY` (at least 8 GB: `STANDARD_L` or larger) and `max_connections` (empty: 500), for the connection budget. For a PostgreSQL you operate: `EXTERNAL`, with its `max_connections` and its memory in GiB (both required, at least 8 GiB; see [install](install.md#bring-your-own-postgresql)) |
| `START_WAIT_SECS` | 900 | how long `SZ_SETUP` and `SZ_START` wait |
| `PG_INSECURE_TLS` | 0 | `1` accepts any server certificate; `SZ_HEALTH` reads `FAIL` until it is `0`. Never for production |

### Sizing

Idle, the app runs two of the cheapest nodes (`GEN_ARM_G1_2`, 1 vCPU, 6 GiB; one node is
0.057 credits/h, about 1.4 credits a day on AWS): one resolver and the replicator, 1 CPU
and up to 5 GiB each (the node's memory less what Snowflake keeps for itself).
Under load the resolver service adds instances, up to `RESOLVER_MAX_INSTANCES`, when the
average resolver uses more than 40% of its CPU for a minute, and removes one when it uses
less than 25% for three minutes; the pool adds nodes up to `POOL_MAX_NODES` to fit them.
CPU scaling does not hold resolvers back when Postgres is the bottleneck: at 6 threads a
resolver waiting on the database still uses 0.4-0.55 of its CPU, so the autoscaler keeps
adding them up to the maximum below. That maximum is what sizes the resolvers to Postgres.
One resolver CPU resolves roughly 35-40 records a second.

Every engine thread holds a Postgres session, and each service 5 more of its own (measured:
a 4-thread resolver holds 9 sessions; a 6-thread one 11), so `RESOLVER_MAX_INSTANCES` x (threads + 5) plus the
replicator's (threads + 5) and the setup job's 4 must fit Postgres. `STANDARD_L` allows 80:
4 resolvers x 11 + 11 + 4 = 59 at 6 threads. A resolver's threads mostly wait on Postgres
(at 4 threads one used about half its CPU and 0.4 GiB), so 6 threads per CPU get more from
each node.

The resolver maximum follows Postgres because Postgres, not the resolvers, sets the pace:
the Senzing sizing guidance is 2 engine cores per database core. In a 200,000-record first
load on `STANDARD_L` (2 cores), 4 resolvers ran 172 records a second at a Postgres load of
7; a 5th added 9% and took the load to 18. For a faster first load, size Postgres up (the
infrastructure script's `SZ_PG_FAMILY`, then `SZ_CONFIGURE({'PG_COMPUTE_FAMILY': ..})`):
the maximum and the pool follow it. The install script tells the app the family of the
Postgres instance it created. The app cannot see your Postgres instance, so after you
resize it yourself, `SZ_CONFIGURE({'PG_COMPUTE_FAMILY': '<family>'})` is what moves the
limits: without it the resolvers stay sized for the old family (too few after sizing up;
too many for the database after sizing down).
Empty `RESOLVER_MAX_INSTANCES` derives it from the database's cores; a number you set replaces
it and is reached under load whatever Postgres is doing. Past 2 resolver CPUs per core the
gain is small (on `STANDARD_L` a 5th resolver added 9%); where more resolvers start to cost
throughput or Postgres starts to fail has not been measured, so stay near that ratio and
size Postgres up for more. `STANDARD_L` has 2 cores: in a 200,000-record first load its load
average reached 4 with three resolvers, so past three or four resolvers a larger
`PG_COMPUTE_FAMILY` buys more throughput than more resolvers.
`SZ_SET_CONFIG`, `SZ_CONFIGURE` and `SZ_START` refuse (`-20024`, naming the numbers) a
configuration that needs more sessions than `PG_MAX_CONNECTIONS` less 10 or more than 10 per
GiB of `PG_COMPUTE_FAMILY`'s memory, or a CPU or memory request larger than one
`POOL_FAMILY` node. Set `PG_COMPUTE_FAMILY` to your instance's family so the budget is real.

Postgres needs at least 8 GB: `STANDARD_L` (2 cores, 8 GB, 40,000 IOPS, 0.0712 credits/h on AWS) or larger; burstable families are not supported (CPU throttling, 100 GB storage cap); a smaller `PG_COMPUTE_FAMILY` is refused and
`SZ_HEALTH` fails `PG_TOO_SMALL` (48 engine sessions ran a `BURST_S` out of memory). For a
large first load use `STANDARD_XL` or larger, then size it back down.

Postgres storage is billed on what is allocated, not what is used: the infrastructure
script allocates twice what `SZ_EXPECTED_RECORDS` needs at about 12 KB a record (1,000,000
records by default: 23 GB; at least 10 GB), or exactly `SZ_PG_STORAGE_GB` when you set it.
Set `SZ_EXPECTED_RECORDS` before the first run: a larger allocation cannot be undone.
`SZ_HEALTH` warns `PG_DISK_HIGH` once the database uses 75% of it. Snowflake grows it on its own when the disk
is nearly full (85% used with less than 50 GB free, or 90% used), by 25% for a 100 GB to
999 GB disk and 15% above that, and puts the instance in read-only mode while it does.
It never shrinks it. To grow it at a time you choose instead, watch the disk and resize
first: `ALTER POSTGRES INSTANCE SZ_PG SET STORAGE_SIZE_GB = <gb>`, then
`CALL <app>.API.SZ_CONFIGURE({'PG_STORAGE_GB': '<gb>'})` so `PG_DISK_HIGH` uses the new size
([Snowflake Postgres maintenance](https://docs.snowflake.com/en/user-guide/snowflake-postgres/postgres-maintenance)).

Resizing and server settings go in separate statements. The instance restarts for a resize;
the resolvers and the replicator reconnect on their own and resume within about 60 seconds
of Postgres returning. Then tell the app the new family: the resolver maximum and the pool
follow it at once, without a restart (`STANDARD_XL`, 4 cores: 8 resolvers, 10 nodes):

```sql
ALTER POSTGRES INSTANCE SZ_PG SET COMPUTE_FAMILY = 'STANDARD_XL';
CALL SZ_SNOWFLAKE.API.SZ_CONFIGURE({'PG_COMPUTE_FAMILY': 'STANDARD_XL'});
-- an instance created before the infrastructure script turned JIT off:
ALTER POSTGRES INSTANCE SZ_PG SET POSTGRES_SETTINGS = '{"postgres:jit": "off"}';
```

An upgrade keeps every setting you already have, including an earlier release's defaults;
to adopt these, set them with `SZ_CONFIGURE`.

**Removing a source's records.** `SZ_PURGE_SOURCE` deletes every record of one data source
from the repository, for example the records an earlier install left in a reused
`PG_DATABASE` (`SZ_HEALTH` `EXISTING_RECORDS`) or a source you no longer want. The resolver
deletes them through the engine, so the entities they were in re-resolve and the replica
follows. Unregister a registered source first:

```sql
CALL SZ_SNOWFLAKE.API.SZ_UNREGISTER_SOURCE('<CODE>');   -- only when it is registered
CALL SZ_SNOWFLAKE.API.SZ_PURGE_SOURCE('<CODE>');
SELECT PURGES FROM SZ_SNOWFLAKE.API.SZ_HEALTH;   -- state PENDING, RUNNING, DONE or FAILED; records_deleted
```

Calling it again re-requests the purge (a `FAILED` one, or a `RUNNING` one whose resolver
stopped).

**Who did what.** `SZ.SZ_APPLY_LOG` is the replicator's record, one row per claim it
applied (`INSTANCE` is a replicator instance; resolver instances never appear there). A
resolver instance's work is in `SZ.SZ_BATCH`: `INSTANCE` names the instance that claimed the
batch and stays set when it is `DONE`, e.g. `SELECT INSTANCE, COUNT(*) AS BATCHES,
SUM(OK_COUNT) AS RECORDS FROM SZ_SNOWFLAKE.SZ.SZ_BATCH WHERE STATE = 'DONE' GROUP BY 1`.

**`CLAIM_MAX_WAIT_SECS` and latency.** The replicator does not apply every resolved entity
at once: it claims a batch when 50,000 ids are queued or when the oldest queued id has
waited `CLAIM_MAX_WAIT_SECS`, whichever comes first. Each apply scans the replica, so
fewer, larger claims are cheaper per id. A trickle of changes therefore reaches the replica
at most `CLAIM_MAX_WAIT_SECS` after it is resolved. Shorten it (`SZ_SET_CONFIG(
'CLAIM_MAX_WAIT_SECS', '20')`) for an interactive demo. For a large load, raise it (at most
900) when `SZ_APPLY` is the bottleneck: `SELECT INSTANCE, APPLY_SECS, ENTITIES_LIVE FROM
SZ_SNOWFLAKE.SZ.SZ_APPLY_LOG ORDER BY APPLIED_AT DESC LIMIT 20` showing many applies of a
few hundred entities that each take tens of seconds means the claims are too small.

### Pause to save money

Idle cost is the compute pool's nodes and Postgres. Pausing suspends both: the services and
pool (`SZ_SUSPEND`), then the Postgres instance. What remains is Postgres storage and small
serverless tasks (billed per second at 0.9x): the hourly prune (about 0.05 credits a day
measured), the auto-pause check and capture, which runs only when a source changes. The
app's health task does no work while paused (running, it measured about 0.4 credits a day). Pause and unpause are procedures
the infrastructure script creates in your `SZ_INFRA_DB.SZ_INFRA` (`<SZ_PREFIX>_INFRA_DB`; the
examples use the default prefix `SZ`) (only you can suspend your
Postgres instance). Suspending a Postgres instance stops every database in it: if anything
else uses the same instance, set `SZ_PG_SHARED = 'YES'` in the infrastructure script and run
its `INSTALL` section again. Pause, unpause and auto-pause then suspend and resume only the
app's services and pool and never the Postgres instance (you suspend and resume it
yourself); the saving is the pool's, about 2.7 credits a day on AWS for the two idle nodes.
A database you operate (`SZ_PG_MODE = 'EXTERNAL'`) is never touched either.

```sql
CALL SZ_INFRA_DB.SZ_INFRA.SZ_PAUSE();     -- suspend the app, wait for the services, suspend SZ_PG
CALL SZ_INFRA_DB.SZ_INFRA.SZ_UNPAUSE();   -- resume SZ_PG, wait until READY (3-5 min), resume the app
SELECT CONVERT_TIMEZONE('America/New_York', AT) AS AT_ET, ACTION, TRIGGERED_BY, DETAIL
  FROM SZ_INFRA_DB.SZ_INFRA.SZ_PAUSE_LOG ORDER BY AT DESC LIMIT 20;
```

**Auto-pause is on by default.** A task (`SZ_AUTO_PAUSE_TASK`, every
`SZ_AUTO_PAUSE_CHECK_MINUTES`, 10, while running and every `SZ_AUTO_PAUSE_PAUSED_CHECK_MINUTES`,
60, while paused) pauses the
install after `SZ_IDLE_PAUSE_MINUTES` (30) with everything resolved and no new change, and
unpauses it when new changes are captured (capture keeps running while paused, so
`SZ_HEALTH.BATCHES_READY` or `QUEUED_KEYS` shows the waiting work). The cost: the first
change after a pause waits up to the paused check interval plus 3-5 minutes for Postgres and
the pool to resume. After hours paused, Snowflake can take longer to provision the pool's
nodes (19 and 30 minutes have been observed). The check does not wait for them: it starts
the services, logs `unpause_started` and finishes the unpause (`unpause`) at the first check
after Snowflake reports them `READY`. While paused the app's watch and retention tasks are suspended too; only
capture and this check run. It never
re-pauses within the idle window after an unpause, never pauses while setup runs or before
the services are `READY`, counts the idle time from the latest capture, apply, setup run,
`SZ_START`/`SZ_RESUME` or source registration (`SZ_HEALTH.LAST_ACTIVITY_AT`) and leaves alone an app you stopped or
suspended by hand. To turn it off, or change the minutes, set the variables at the top of
the infrastructure script and run its `INSTALL` section again:

```sql
SET SZ_AUTO_PAUSE = 'OFF';               -- or 'ON'
SET SZ_IDLE_PAUSE_MINUTES = 60;          -- 10..1440
SET SZ_AUTO_PAUSE_CHECK_MINUTES = 10;    -- 5..60: while running
SET SZ_AUTO_PAUSE_PAUSED_CHECK_MINUTES = 60;  -- 5..1440: while paused; shorter wakes sooner, costs more
```

The task runs as the role that ran the script, which needs `OPERATE` (or ownership) on
`SZ_PG` and the app's `APP_ADMIN` role (the install script grants it to `--operator-role`,
by default your role). Capture keeps reading your source tables' streams while paused, so a
stream does not go stale; if one does after a very long pause, `SZ_UNPAUSE` repairs it (the
app's `SZ_RESUME` re-registers stale sources).

## Upgrade

A later build of the same Senzing SDK version (`4.4.3-1` to `4.4.3-2`): download and verify the
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

A new Senzing SDK
version (`4.4.4-1`) is `REGISTER VERSION V4_4_4 .. LABEL = '4.4.4-1'`, added to the
`DEFAULT` channel, then the same directive, upgrade and `SZ_UPGRADE`; deregister `V4_4_3`
once no app reports it (a channel holds two versions). Verify: `SZ_HEALTH.UPGRADE_PENDING`
clears and `OVERALL` is `OK`; no version stays `FINALIZING` in `SHOW VERSIONS IN APPLICATION
PACKAGE SZ_SNOWFLAKE_PKG`. `SZ_UPGRADE` stops at the first failing step and resumes there
when you call it again.

A release that carries a new version of the Senzing End User License Agreement (EULA) needs
a new acceptance: `SZ_UPGRADE`
returns `FAILED` with `-20109` until `CALL SZ_SNOWFLAKE.API.SZ_ACCEPT_EULA('I_ACCEPT_THE_SENZING_EULA')`
runs, then resumes when called again. The install script checks this after `ALTER APPLICATION
.. UPGRADE`: it stops with the `CALL` to run, or runs it with `--accept-eula`.

## Teardown

`DROP APPLICATION .. CASCADE` removes what the app created in Snowflake but not the Senzing
database in your Postgres instance, and only the app's setup job holds the admin login that
can drop it. So drop it through the app first (the argument is your `PG_DATABASE`, as a
confirmation; it stops the services first and refuses while one is still running). A
paused install needs Postgres: unpause it first.

```sql
CALL SZ_INFRA_DB.SZ_INFRA.SZ_UNPAUSE();   -- only when paused
CALL SZ_SNOWFLAKE.API.SZ_UNINSTALL('senzing');
DROP APPLICATION IF EXISTS SZ_SNOWFLAKE CASCADE;
DROP APPLICATION PACKAGE IF EXISTS SZ_SNOWFLAKE_PKG;
DROP DATABASE IF EXISTS SZ_SNOWFLAKE_PKG_DB;
```

Then the infrastructure script's `TEARDOWN` section (`SET SZ_INCLUDE_POSTGRES = 'NO'` keeps
the Postgres instance). Verify: `SHOW APPLICATIONS`, `SHOW APPLICATION PACKAGES`, `SHOW
COMPUTE POOLS`, `SHOW WAREHOUSES LIKE 'SZ_SNOWFLAKE_WH'`, `SHOW POSTGRES INSTANCES`, `SHOW NETWORK
POLICIES` and `SHOW EXTERNAL ACCESS INTEGRATIONS` list nothing of ours.
