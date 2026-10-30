<p>
  <img src="../assets/senzing-logo.jpg" alt="Senzing" width="48" align="left" hspace="8">
  <samp><b>SENZING</b></samp>
</p>
<br clear="left">

[sz-snowflake](../README.md) / Install and report with an AI assistant

# Install and report with an AI assistant

An AI coding assistant with a shell and a Snowflake connection (Snowflake Cortex Code,
Claude Code, or similar) can run the whole [path](../README.md#the-path) for you: verify
the release, install the app, register your sources, watch them resolve, and build a
report on the results. You watch and answer its questions; it never accepts the Senzing
EULA on your behalf.

The assistant uses the Snowflake connection it already has, so you do not log in to
Snowflake separately.

<sub><b>MCP AND INPUTS</b></sub>

## Before you start

**Connect the Senzing MCP server.** Add `https://mcp.senzing.com/mcp` (HTTP, no
authentication) to your assistant's MCP servers. It answers Senzing questions (match keys,
match levels, entity specification attributes, error codes) from Senzing's documentation,
so the assistant does not guess. Do not send it personal data or credentials.

Have ready:

|                                                 |                                                                                                                             |
| ----------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| The [prerequisites](../README.md#prerequisites) | a role such as `ACCOUNTADMIN`, the Snowflake CLI, Docker, `cosign`                                                          |
| A release                                       | its tag, e.g. `4.4.3-1`, from this repository's [releases](https://github.com/Senzing/sz-snowflake/releases)                |
| Your sources                                    | per data source: a code (`CUSTOMERS`), a mapping view producing Senzing JSON, and its base table(s) with a record id column |
| A license (optional)                            | base64; without one the engine stops at 500 records                                                                         |

<sub><b>INSTALL</b></sub>

## Prompt 1: install and resolve

Fill in the placeholders and paste:

> Install the Senzing native app on Snowflake, release `<release>`, using my Snowflake
> connection `<connection>`. Use the Senzing MCP tools for any Senzing question; do not
> answer Senzing questions from memory.
>
> 1. Download the release's files from https://github.com/Senzing/sz-snowflake/releases
>    into a new empty directory and verify them exactly as the README's "Verify" section
>    says. Stop if any check fails.
> 2. Show me `sz-snowflake-infra-<release>.sql`, then run it with my connection after I
>    confirm.
> 3. Open https://senzing.com/end-user-license-agreement/ for me and ask whether I accept
>    it. Pass `--accept-eula` in the next step only if I say yes.
> 4. Run `sz-snowflake-install-<release>.sh` (read it and run `--dry-run` first) with
>    `--connection <connection>`, `--pg-host` set to the `PG_HOST` the infrastructure script
>    printed, `--operator-role <role>`, and one `--source` per data source:
>    `--source <CODE>=<db.schema.mapping_view>:<db.schema.table>[:<record id column>]`.
> 5. While setup runs (2 to 5 minutes, one blocking call), check
>    `SELECT SETUP_PHASE, SETUP_RUNNING_SECS FROM SZ_SNOWFLAKE.API.SZ_HEALTH` every 15
>    seconds and tell me the phase in one line.
> 6. Then check every 15 seconds (never longer) and narrate each result in one line:
>    `SELECT RESOLVE_STATE, LAST_CAPTURE_AT, LAST_APPLY_AT, (SELECT COUNT(*) FROM
SZ_SNOWFLAKE.SZ.ENTITY_RECORD) AS RECORDS, (SELECT COUNT(DISTINCT ENTITY_ID) FROM
SZ_SNOWFLAKE.SZ.ENTITY_RECORD) AS ENTITIES FROM SZ_SNOWFLAKE.API.SZ_HEALTH`.
>    Stop when `RESOLVE_STATE` is `CAUGHT_UP` and show me the counts.
>
> If any step fails, show me the error and look it up (the Senzing MCP tools and
> docs/troubleshooting.md in the release repository) before trying again. Every step can
> be re-run.

Never paste a license, password or key into the prompt: set the license secret yourself
([install](install.md#4-set-the-license-secret)).

<sub><b>REPORT</b></sub>

## Prompt 2: a report on your data

When the state reads `CAUGHT_UP`, paste:

> Build a Streamlit app that runs locally on this machine and reports on my source data
> joined with the Senzing results. This is a report on the data, not on the install.
> Connect with Snowpark using my Snowflake connection `<connection>`
> (`Session.builder.config("connection_name", ...)`). Use a Python 3.12 virtual
> environment with `streamlit` and `snowflake-snowpark-python`, start it with
> `streamlit run`, open http://localhost:8501, and confirm every section renders with no
> errors in the terminal.
>
> Results, schema `SZ_SNOWFLAKE.SZ`: `ENTITY_RECORD` (DATA_SOURCE, RECORD_ID, ENTITY_ID,
> MATCH_KEY, empty for an entity's first record), `ENTITY` (ENTITY_ID, RECORD_COUNT),
> `RELATIONSHIP` (ENTITY_ID_LO, ENTITY_ID_HI, MATCH_LEVEL_CODE, MATCH_KEY). Join each
> record to its source row: for data source `<CODE>`, table `<db.schema.table>` on
> `<record id column>` = RECORD_ID. Show readable fields such as name, date of birth,
> address, phone and email.
>
> Sections:
>
> 1. Metrics: source records, entities, percentage of duplicates removed, entities that
>    span more than one data source, relationships.
> 2. Bar chart: entities by data source combination (e.g. "CUSTOMERS + WATCHLIST").
> 3. Bar chart: records per entity.
> 4. Bar chart: why records matched (count by non-empty MATCH_KEY, top 12).
> 5. Bar chart: relationships by MATCH_LEVEL_CODE.
> 6. Table: entities that hold records from both `<CODE A>` and `<CODE B>`, with every
>    record's readable fields and MATCH_KEY.
> 7. Entity explorer: search a name, pick an entity, show its records and why each
>    matched, then the related (not merged) entities' records with MATCH_LEVEL_CODE and
>    MATCH_KEY. Bind user input as query parameters; never build SQL from it.

The report creates nothing in Snowflake; stop the local process to remove it.

| Known issue                                  | Fix                                                          |
| -------------------------------------------- | ------------------------------------------------------------ |
| `snowflake-snowpark-python` will not install | it has no build for the newest Python; use Python 3.12       |
| Streamlit warns about `use_container_width`  | use `width="stretch"`                                        |
| The assistant polls slowly                   | say "check every 15 seconds"; setup alone can take 5 minutes |
