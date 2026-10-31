<p>
  <img src="../assets/senzing-logo.jpg" alt="Senzing" width="48" align="left" hspace="8">
  <samp><b>SENZING</b></samp>
</p>
<br clear="left">

[sz-snowflake](../README.md) / Troubleshooting

# Troubleshooting

Start with the one view that summarizes everything:

```sql
SELECT * FROM SZ_SNOWFLAKE.API.SZ_HEALTH;   -- APP_USER: OVERALL, WARNINGS, one column per check
```

`OVERALL` is `OK`, `WARN` or `FAIL`; `WARNINGS` lists every failing or warning check by
the codes below (the failing ones first). `FAIL_CODES` lists only the codes that make
`OVERALL` read `FAIL`, `WARN_CODES` the rest. `UPGRADE_PENDING` is a `FAIL`: claiming stays
paused until `SZ_UPGRADE` runs (the install script runs it when a re-run changes the patch).

<sub><b>FIRST STOP</b></sub>

## Where to look

| Failure | Read |
|---|---|
| a setup job | `SELECT RUN_ID, MODE, EXIT_CODE, RESULT:reason, RESULT:error, RESULT:log_tail FROM SZ_SNOWFLAKE.SZ.SZ_SETUP_LOG ORDER BY STARTED_AT DESC LIMIT 1` (`APP_ADMIN`; the log tail is the container's raw output) |
| a service that failed or parked | `SELECT ROLE, INSTANCE, STATE, PAYLOAD:exit, WRITTEN_AT FROM SZ_SNOWFLAKE.SZ.SZ_SERVICE_STATUS` (also `SZ_HEALTH.STATUS_ROWS` and `LAST_FAILED_EXIT`) |
| a service's status and log by hand | `SHOW SERVICES IN APPLICATION SZ_SNOWFLAKE`, `SELECT SYSTEM$GET_SERVICE_STATUS('SZ_SNOWFLAKE.SZ.SZ_RESOLVER_SVC')` and `SYSTEM$GET_SERVICE_LOGS(..)` for a role granted `APP_ADMIN` (the app grants it `MONITOR` on its services and the setup job) |
| a container's log | your event table: `SELECT TIMESTAMP, RESOURCE_ATTRIBUTES:"snow.service.name", VALUE FROM SNOWFLAKE.TELEMETRY.EVENTS WHERE RECORD_TYPE = 'LOG' AND RESOURCE_ATTRIBUTES:"snow.database.name" = 'SZ_SNOWFLAKE' ORDER BY TIMESTAMP DESC LIMIT 200` (the app sends every container log there) |
| the capture task | `SZ_HEALTH.CAPTURE_TASK_STATE`, `CAPTURE_LAST_ERROR`, `SOURCE_ERRORS`; `SZ_WATCH` refreshes them every 10 minutes |
| the replica | `SELECT INSTANCE, APPLY_SECS, ENTITIES_LIVE FROM SZ_SNOWFLAKE.SZ.SZ_APPLY_LOG ORDER BY APPLIED_AT DESC LIMIT 20` (one row per replicator claim: only replicator instances appear) |
| one resolver instance's work | `SELECT INSTANCE, STATE, COUNT(*), SUM(OK_COUNT) FROM SZ_SNOWFLAKE.SZ.SZ_BATCH GROUP BY 1, 2` (`INSTANCE` stays set on `DONE` batches) |

<sub><b>BY SYMPTOM</b></sub>

## Symptoms

| Symptom | Cause and fix |
|---|---|
| The setup job or a service cannot reach Postgres (`pg_connect`, a 10 s connect timeout) | a missing or stale ingress rule: a connect timeout, never a refusal. `CALL SZ_INFRA_DB.SZ_INFRA.SZ_REFRESH_PG_INGRESS()` and check `SZ_PG_INGRESS_TASK` is `started`; the egress rule must name exactly `<PG_HOST>:5432` |
| `SZ_REGISTER_SOURCE` raises `-20203` / `-20204`: `... is not bound in SOURCE_VIEWS` (or `SOURCE_TABLES`) | the view or table you named has no binding (or the name differs: it must be the full `DB.SCHEMA.NAME`); run the `REGISTER_REFERENCE` call the message names, then register again |
| the install script stops at P2 (`CREATE DATABASE` / `CREATE SCHEMA` refused) | the role cannot create the package database: re-run with `--role ACCOUNTADMIN` (or another role that can create a database, an application package and an application) |
| after a re-install, a procedure the new release has is `Unknown user-defined function` | the app runs an older build registered under the same release label. The install script now registers a new patch (`<release>+<fingerprint>`) when the bundle's files differ from what the patch was registered from; re-run it with the new bundle |
| P3 seems stuck | each image push takes minutes; the script prints a line every 30 s per push and each image's finish time |
| `SZ_CONFIGURE` raises `-20023` | nothing was changed; the message lists every bad name or value. Fix them all and call it again |
| `SZ_SET_CONFIG` / `SZ_CONFIGURE` / `SZ_START` raises `-20024` (sizing) | nothing was changed; the message names each problem with its numbers: a CPU or memory request larger than one `POOL_FAMILY` node, or more Postgres sessions than the budget ([Sizing](use.md#sizing)). Change the settings together in one `SZ_CONFIGURE` |
| every resolver connection fails (`out of memory`, `could not load library llvmjit.so`, the SSL handshake refused); resolvers stay `STARTING` | Postgres is too small for the sessions: `BURST_*` has 2-4 GB and is not supported. Resize it (at least `STANDARD_L`, `STANDARD_XL` for a large load) and turn JIT off, in separate `ALTER POSTGRES INSTANCE` statements ([Sizing](use.md#sizing)); set `PG_COMPUTE_FAMILY` so the budget check knows |
| the infrastructure script stops at I7 with `-20908` | `SZ_PG_FAMILY` has less than 8 GB. Postgres needs at least 8 GB: `STANDARD_L` (2 cores, 8 GB, 40,000 IOPS, 0.0712 credits/h on AWS) or larger; burstable families are not supported (CPU throttling, 100 GB storage cap) |
| the first change after a quiet period takes minutes to appear | auto-pause: the install was paused and is resuming (up to the 10-minute check, then Postgres 3-5 minutes and the services). `SZ_INFRA_DB.SZ_INFRA.SZ_PAUSE_LOG` shows it; turn it off with `SZ_AUTO_PAUSE = 'OFF'` ([Pause to save money](use.md#pause-to-save-money)) |
| `SZ_PAUSE` / `SZ_UNPAUSE` raise `-20920` .. `-20922` | `-20920`: no application name recorded (re-run the infrastructure script with `SZ_APP`); `-20921`: the services did not suspend in 10 minutes (call `SZ_PAUSE` again); `-20922`: Postgres not `READY` after 20 minutes (call `SZ_UNPAUSE` again). `SZ_PAUSE_LOG` has the details |
| `SZ_UNINSTALL` raises `-20110` | the argument is not your `PG_DATABASE` (the message names it), or the services did not suspend in time; nothing was dropped |
| `SZ_SETUP` seems to hang | it is one blocking call (2 to 5 minutes). In another worksheet, `SELECT SETUP_PHASE, SETUP_RUNNING_SECS FROM SZ_SNOWFLAKE.API.SZ_HEALTH`: `waiting_for_job_container` means the pool is bringing up a node or pulling the image; any other value is the job's phase. Afterwards the result's `timing` (and `SZ_SETUP_LOG.RESULT:phases`) says which phase took the time |
| results do not appear (`RESOLVE_STATE` stays `WAITING_FOR_CAPTURE` or `RESOLVING`) | `WAITING_FOR_CAPTURE`: the capture task has not cut the keys yet (it waits up to `CUT_MAX_AGE_SECS`; check `CAPTURE_TASK_STATE` is `started`); `RESOLVING`: batches wait for the resolver (`BATCHES_READY`, `SERVICE_STATE`) or results for the replicator; `OVERALL` names any failure |
| setup exit 7 `precondition`: `the repository server is PostgreSQL 16..` | the app needs PostgreSQL 17 or later; upgrade your database (Snowflake Postgres: `POSTGRES_VERSION = 17` or later) |
| the infrastructure script stops with `-20914` | `SZ_PG_MODE = 'EXTERNAL'` needs `SZ_PG_HOST` (a host name) and `SZ_PG_PORT` |
| `SZ_SET_CONFIG` / `SZ_START` raise `-20024` naming `PG_EXTERNAL` | `PG_COMPUTE_FAMILY` `EXTERNAL` needs `PG_MEMORY_GIB` and `PG_MAX_CONNECTIONS` (your database's size) in the same `SZ_CONFIGURE` |
| `SZ_PURGE_SOURCE` raises `-20209` | the code is malformed, or the source is registered and enabled: `SZ_UNREGISTER_SOURCE('<CODE>')` first (its records would otherwise come back) |
| `SZ_REGISTER_SOURCE` raises `-20208` | change tracking is off on a source table; nothing was registered. The message carries the statement: as the table owner run `ALTER TABLE <db>.<schema>.<table> SET CHANGE_TRACKING = TRUE;`, then call `SZ_REGISTER_SOURCE` again with the same arguments |
| `RESOLVE_STATE` reads `SOURCES_FAILED` | a source's capture failed (`SOURCE_ERRORS`: usually change tracking turned off, or a stale stream). Fix what it says, then `SZ_REGISTER_SOURCE` again with the same arguments; `RESOLVE_STATE` never reads `CAUGHT_UP` meanwhile |
| setup fails `unsafe_login` (`CREATE on database ..` through `snowflake_write`) | an older release: Snowflake Postgres' `RESET ACCESS` adds the `application` login to `snowflake_write`, which may create schemas. This release's setup revokes that grant; after the infrastructure script's `ROTATE` run `SZ_SETUP('install')` again to revoke it once more |
| records you never loaded appear (`SZ_HEALTH` `EXISTING_RECORDS`) | `PG_DATABASE` held an earlier install's data; `LAST_SETUP_WARNINGS` names them. Start clean with `SZ_UNINSTALL('<PG_DATABASE>')` or a new `PG_DATABASE` |
| capture for one source stops (`SOURCES_FAILED` / `SOURCES_STALE`) | change tracking turned off after registration, or the stream went stale; `SOURCE_ERRORS` carries the fix; `SZ_REGISTER_SOURCE` again repairs it |
| `SZ_SETUP` / `SZ_START` refuses with `-20109` (the Senzing End User License Agreement is not accepted) | read https://senzing.com/end-user-license-agreement/, then `CALL SZ_SNOWFLAKE.API.SZ_ACCEPT_EULA('I_ACCEPT_THE_SENZING_EULA')` as `APP_ADMIN` ([install](install.md#3-accept-the-senzing-eula)). After an upgrade it means the new release carries a new EULA version: accept again, then re-run (`SZ_UPGRADE` resumes at its step) |
| `SZ_ACCEPT_EULA` raises `-20109` | the value was not exactly `I_ACCEPT_THE_SENZING_EULA` (upper case, no spaces) |
| `SZ_SETUP` / `SZ_START` refuses with `-20102`, naming a reference | the reference or secret is not bound; bind it ([install](install.md#2-install-from-the-bundle)) and re-run |
| `SZ_SETUP` raises `-20101` | the job failed or never ran: the message starts with `reason=.. error=..`; the full result is in `SZ_SETUP_LOG` (above). Reasons below |
| `SZ_SETUP` raises `-20108` | a setup run is still in progress; wait, or read `SZ_SETUP_LOG` |
| `SZ_START` / `SZ_RESUME` raises `-20107` | the services did not reach `READY` within `START_WAIT_SECS`; the message carries both statuses. Read `SZ_SERVICE_STATUS` (a `FAILED` row's `exit` line names the reason and the fix) and the container log |
| `SZ_START` raises `-20103` | no successful install or upgrade setup run yet: `SZ_SETUP('install')` first |
| `SZ_UPGRADE` returns `FAILED, step n` | fix what `error` names and `CALL SZ_UPGRADE()` again: it resumes at that step. Step 1 `live instances`: the suspended services had not stopped yet; wait a minute and re-run |
| `SZ_SET_CONFIG('PG_INSECURE_TLS', '1')` | returns a warning and `SZ_HEALTH` reads `FAIL (PG_INSECURE_TLS)` until it is `0` again: the services then accept any server certificate. Never a production setting |

### Setup reasons (`SZ_SETUP_LOG`, `RESULT:reason`)

| Reason or exit | Meaning and fix |
|---|---|
| `pg_connect` | the `PG_EAI` egress rule or the `SZ_PG_INGRESS` policy does not admit the app: the infrastructure script's egress and ingress sections |
| `pg_tls` | `PG_CA_SECRET` is not the instance's CA: re-copy it (the script's `ROTATE` section) and `SZ_RELOAD_SECRETS()` |
| `pg_auth` | `PG_ADMIN_SECRET` or `PG_APP_SECRET` is not the generated password: re-run the script's secrets section |
| `pg_ca/secret_string: missing` (a service's exit line) | the CA file is required unless `PG_INSECURE_TLS` is set; bind `PG_CA_SECRET` |
| exit 7 `precondition` | services are live during an upgrade or an uninstall (an instance that crashed counts as live for 15 minutes), or a relation in `public`/`sz_snowflake` is not owned by `sz_owner` |
| exit 8 `ddl` | a Postgres statement failed: it is in `error` |
| exit 1 `deadline` | a lock wait or a hung server outlived the setup deadline (300 s by default) |
| exit 1 `unsafe runtime login` | the `application` login holds a privilege it must not; `error` shows the ACL |
| a job that never scheduled | `error` carries the pool's message (`Unschedulable ..`): raise `START_WAIT_SECS` or check `POOL_FAMILY` (an ARM family for `linux/arm64`) |

<sub><b>REFERENCE</b></sub>

## `SZ_HEALTH` codes

`OVERALL` is `FAIL` when any of the first group is present, `WARN` for the second.

| Code | Means | Fix |
|---|---|---|
| `EULA_NOT_ACCEPTED` | the Senzing EULA version of this release is not accepted (`EULA_VERSION`; `EULA_ACCEPTED_AT` and `EULA_ACCEPTED_BY` are empty) | `CALL SZ_SNOWFLAKE.API.SZ_ACCEPT_EULA('I_ACCEPT_THE_SENZING_EULA')` as `APP_ADMIN` |
| `REFERENCES_MISSING` | a required reference was unbound (names it) | bind it again |
| `UPGRADE_PENDING` | `ALTER APPLICATION .. UPGRADE` ran (or a new patch reached the app), `SZ_UPGRADE` has not finished; claiming stays paused | `CALL SZ_UPGRADE()`; the install script runs it when a re-run changes the patch |
| `PG_INSECURE_TLS` | the setting is `1`: no certificate verification | `SZ_SET_CONFIG('PG_INSECURE_TLS', '0')`, then `SZ_RELOAD_SECRETS()` |
| `CAPTURE_TASK` | `SZ_CAPTURE_TASK` is not `started`, or its last run failed (`CAPTURE_LAST_ERROR`) | `SZ_START` resumes the tasks; the error names the statement |
| `SOURCES_FAILED` | a source's capture failed (`SOURCE_ERRORS`); `RESOLVE_STATE` reads `SOURCES_FAILED` too | usually change tracking: run the statement, `SZ_REGISTER_SOURCE` again with the same arguments |
| `PURGE_RUNNING` | a `SZ_PURGE_SOURCE` request is `PENDING` or `RUNNING` (`PURGES`) | wait; a resolver takes it. A `RUNNING` one that does not move while its resolver is gone (`STATUS_ROWS`): call `SZ_PURGE_SOURCE` again |
| `PURGE_FAILED` | a purge stopped (`PURGES` has the error and the records deleted so far) | fix the cause, then `SZ_PURGE_SOURCE` again: it resumes |
| `EXISTING_RECORDS` | the newest `SZ_SETUP('install')` found records of data sources this app has not registered (an earlier install's) in `PG_DATABASE` (`LAST_SETUP_WARNINGS`) | keep them; remove one source's with `SZ_PURGE_SOURCE('<CODE>')` ([use](use.md#register-a-source)); or start clean: `SZ_UNINSTALL` or a new `PG_DATABASE` |
| `SOURCES_STALE` | a source stream is stale or within 2 days of it | `SZ_REGISTER_SOURCE` again (`SZ_RESUME` repairs stale sources itself) |
| `SERVICE_STATE` | a container is not `READY` while not suspended | the container log; `SZ_START` re-points and resumes |
| `STATUS_FAILED` | a service instance wrote a `FAILED` row (`LAST_FAILED_EXIT`: reason, code, hint) | fix what the hint names; `SZ_START` clears the old rows |
| `PG_TOO_SMALL` | `PG_COMPUTE_FAMILY` has less than 8 GB (`BURST_*`, `STANDARD_M`): not supported | `ALTER POSTGRES INSTANCE SZ_PG SET COMPUTE_FAMILY = 'STANDARD_L'` (or larger), then `SZ_SET_CONFIG('PG_COMPUTE_FAMILY', 'STANDARD_L')` |
| `PG_UNREACHABLE` | a service ended on a Postgres error (`LAST_FAILED_EXIT` reads `reason=pg..`: connect, TLS, login, or the server refused the session) | the setup reasons below; a server out of memory or sessions: [Sizing](use.md#sizing) |
| `PARKED` | a resolver parked (`parked_reason`: the license record limit or expiry), or the replicator parked on `shape_mismatch` | license: set `SZ_LICENSE`, `SZ_RELOAD_SECRETS()`; shape: `CALL SZ_RESYNC()` rebuilds the replica and un-parks the replicator |
| `DEGRADED` | a resolver instance reports `DEGRADED` (engine or repository errors) | `SZ_STATUS()` and the container log |
| `SHAPE_MISMATCH` | the replica's layout is not this version's | `CALL SZ_RESYNC()` |
| `SOURCES_NOT_REGISTERED` | a source's code is not yet registered in the engine | wait for the resolver's first batch; then the container log |
| `CLAIMING_PAUSED` | claiming is paused outside an upgrade or suspend (an abandoned `SZ_PREPARE_UPGRADE`) | `SZ_START` or `SZ_RESUME` clears it |
| `WATCH_ERRORS` | a `SZ_WATCH` probe failed (`WATCH_ERRORS` lists them); that check kept its previous value | read the error; it is never reported as the condition it could not check |
| `STATUS_STALE` | no resolver status for 2 hours while running | the container log; `SZ_STATUS()` |
| `IMAGE_MISMATCH` | containers run more than one image release, or not the one setup ran | finish the upgrade (`SZ_UPGRADE`, `SZ_START`) |
| `PENDING_OLD` | the oldest pending key is over an hour old | resolvers down or parked (above), or `BACKLOG_*` sizing |
| `LEASES_EXPIRED` | a claimed batch outlived its lease (a resolver died mid-batch) | the next cut re-batches it; check `STATUS_ROWS` |
| `REJECTED_KEYS` | records the engine rejected (`SZ.SZ_RESULT` has the reason per key) | fix the records; `SZ_REQUEUE_REJECTED('<CODE>')` |
| `DEAD` | entities or redo records that failed `TIMEOUT_MAX_ATTEMPTS` times | the container log; `SZ_RESYNC()` after the cause is fixed |
| `STARTING_STUCK` | an instance has been `STARTING` longer than `START_WAIT_SECS`: it is still retrying its Postgres connect | Postgres down, full or out of memory; the container log names the error |
| `CONNECTION_BUDGET` | `CONNECTION_DEMAND`, the sessions the services can hold at `RESOLVER_MAX_INSTANCES`, exceeds `CONNECTION_BUDGET` | lower `RESOLVER_MAX_INSTANCES` or the threads, or size Postgres up and set `PG_COMPUTE_FAMILY` |
| `APPLY_LAG` | work queued and no apply for an hour | replicator down (above), or the warehouse: `SZ_WATCH` sizes `<APP>_WH` up when an apply passes `APPLY_SLOW_SECS` |

**Reading the replicator.** `SZ_APPLY` refuses a claim whose shape does not match
(`SHAPE_MISMATCH`, `-20603`), whose staged rows are incomplete (`STAGE_INCOMPLETE`,
`-20641`) or that fails any statement; the replicator releases that claim at once and, on a
shape mismatch, parks until `SZ_RESYNC` runs, which `SZ_HEALTH` shows as `PARKED`.
