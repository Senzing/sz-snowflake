<p>
  <img src="assets/senzing-logo.jpg" alt="Senzing" width="48" align="left" hspace="8">
  <samp><b>SENZING</b></samp>
</p>
<br clear="left">

# sz-snowflake

**Entity resolution inside your own Snowflake account. Senzing hosts nothing and receives nothing.**

> [!TIP]
> **Let your AI assistant do the install.** Snowflake Cortex Code, Claude Code or any
> assistant with a shell and a Snowflake connection can run the whole path for you:
> verify the release, install the app, register your tables, watch them resolve, and
> build a report on your own data joined with the results. You paste two prompts and
> answer its questions; it never accepts the Senzing EULA for you. Connect the
> [Senzing MCP server](https://mcp.senzing.com/mcp) so its Senzing answers come from
> Senzing's documentation.
>
> **Start here: [install and report with an AI assistant](docs/ai-assisted.md)**

> [!IMPORTANT]
> **Public Preview.** sz-snowflake is provided as-is, without warranty of any kind and
> without a support commitment. Its interfaces, settings and release files can change
> between releases. Use is governed by the
> [Senzing End User License Agreement](https://senzing.com/end-user-license-agreement/).

Senzing entity resolution as a Snowflake Native App that you build and install
yourself, running on Snowpark Container Services with Snowflake Postgres as the
Senzing repository. Each release is **one download** of about 0.3 GB: the signed bundle for
your compute pool's architecture, holding the app files and the three container images, which you push to your own Snowflake image
repository. No source code is published, and nothing is pulled from a public registry.

This page is the guide for doing it by hand. The steps are in [docs/install.md](docs/install.md), day-to-day
use in [docs/use.md](docs/use.md), and what to do when something fails in
[docs/troubleshooting.md](docs/troubleshooting.md).

<sub><b>RELEASE ASSETS</b></sub>

## What a release contains

| Asset | Content |
|---|---|
| `sz-snowflake-<release>-linux-arm64.tar.gz`, `sz-snowflake-<release>-linux-amd64.tar.gz` | one bundle per architecture, about 0.3 GB each; **download only the one for your compute pool**: `linux-arm64` for the default pool (`GEN_ARM_G1_2`, any `GEN_ARM_*`; offered on AWS, Azure and Google Cloud), `linux-amd64` for an x86 `POOL_FAMILY`. Each holds `app/` (the Native App files: `manifest.yml`, `setup_script.sql`, `services/*.yaml`, `README.md`, `SHA256SUMS`), `images/<arch>/sz-snowflake-images.tar` (the three images as one docker archive; their shared layers stored once), the infrastructure script and the install script |
| `sz-snowflake-infra-<release>.sql` | the infrastructure script you run and own (Postgres instance, network rules, policy, integration, secrets), also on its own so you can read it before downloading the bundle |
| `sz-snowflake-install-<release>.sh` | the package build and install steps, each printed before it runs |
| `sz-snowflake-cord-data.tar.gz` | optional: the CORD data for the Senzing Snowflake preview, Senzing's official [CORD](https://senzing.com/senzing-ready-data-collections-cord/) data reshaped into normalized source tables (one directory of CSV files per source system) with `load.sql` to load it (extract with `tar -xzf`, built into macOS, Linux and Windows 10 and later); see [No data of your own?](#no-data-of-your-own-use-the-cord-data) |
| `SHA256SUMS`, `*.sigstore.json` | checksums, and a keyless cosign signature for every file above |

An earlier release may carry one bundle with both architectures, `sz-snowflake-<release>.tar.gz`;
the install script takes either.

A release is named `<senzing_version>-<build>`, for example `4.4.3-7`: the Senzing
version it carries and a build counter that restarts at 1 for each Senzing version.
`4.4.3-10` is a later build than `4.4.3-7`.

<sub><b>CONTAINERS</b></sub>

## Images

| Image | Runs as | Does |
|---|---|---|
| `sz-snowflake-setup` | job | creates and migrates the Postgres side; the only image that runs DDL |
| `sz-snowflake-resolver` | service, N instances | loads changed records into Senzing |
| `sz-snowflake-replicator` | service, M instances | writes resolved entities back to Snowflake tables |

All three: base `gcr.io/distroless/cc-debian13:nonroot` (no shell, no package
manager, uid 65532), built natively for each architecture, with the Senzing runtime at
the version in the release's name. Each binary has a `version` command. The install
script pushes the target architecture's three images to your image repository as
`sz-snowflake-<role>:<release>`; use the ARM images with an ARM compute pool family.

<sub><b>TRUST</b></sub>

## Trust model

| Rule | |
|---|---|
| Everything runs in your account | compute, Postgres, data, logs, status |
| Senzing hosts nothing and receives nothing | Senzing publishes software only: these images and the release files |
| No telemetry | no phone-home, license check or update check; the app declares no event definitions |
| One egress | your own Postgres host on port 5432, through an external access integration you create and can disable at any time |
| Your secrets stay yours | the app has `READ` only. Snowflake injects them into the containers as read-only files; they are never passed as environment variables, never logged, and read once at start (a rotation restarts the services) |
| Your license is your secret | stored in your Snowflake secret; logs show only its expiry date and record limit |
| No volumes | the containers read their image, the Snowflake session token and the injected secret files, and write two small TLS settings files for the Postgres client |

<sub><b>NETWORK</b></sub>

## Postgres exposure

| Control | |
|---|---|
| TLS | `verify-full` against your account's own root CA |
| Login | services use a DML-only login with a generated password; only the setup job uses the admin login |
| Ingress | only your region's Snowflake egress ranges, refreshed daily by a task you own; never `0.0.0.0/0` |
| **Exposure** | those ranges are shared by every Snowflake account in the region, so other tenants' containers can reach the endpoint; the generated password and `verify-full` TLS protect it |
| Upgrade | same-account Private Link (Business Critical, AWS and Azure) removes that exposure; a change to one network rule |

A missing or stale ingress rule shows up as a 10 s connect timeout, not a refusal.

<sub><b>BEFORE YOU START</b></sub>

## Prerequisites

| Need | Note |
|---|---|
| A Snowflake account on AWS or Azure | Snowflake Postgres is not available on GCP |
| A role that can create an application package and application, a Postgres instance, a network policy and an external access integration | `ACCOUNTADMIN` works; a delegated role is possible |
| The Snowflake CLI (`snow`) and Docker (or `skopeo`, or `crane`) | Docker loads the bundle's images and pushes them to your image repository. Pin `snowflake-connector-python<5`: 5.x breaks the image-registry login (or log in to the registry yourself with a PAT) |
| `cosign`, `sha256sum` | to verify the release files |
| Postgres with at least 8 GB | `STANDARD_L` (2 cores, 8 GB, 40,000 IOPS, 0.0712 credits/h on AWS) or larger, the infrastructure script's default; burstable families are not supported (CPU throttling, 100 GB storage cap) |
| A Senzing license (base64) | optional; without one the engine stops at 500 records. Never put it in a committed file |
| Data to resolve | your own tables, or the [CORD data](#no-data-of-your-own-use-the-cord-data) |
| One release's files | download the bundle for your pool's architecture (`linux-arm64` for the default pool), `SHA256SUMS` and the `*.sigstore.json` files from this repository's [releases](https://github.com/Senzing/sz-snowflake/releases) |

## Sizing

Idle, the app runs two of the cheapest compute nodes (`GEN_ARM_G1_2`, 1 vCPU and 6 GiB;
about 1.4 credits a day each on AWS) for one resolver and the replicator, and the Postgres
instance the infrastructure script creates (`STANDARD_L`). Auto-pause is on: after 30
idle minutes the install pauses (pool and Postgres suspended; what remains is Postgres
storage, the hourly prune and the 10-minute auto-pause check) and it resumes when new
changes arrive, within the check interval plus 3-5 minutes. With a Postgres instance other
workloads share, set `SZ_PG_SHARED = 'YES'`: pausing then stops only the pool (about 2.7
credits a day saved) and never Postgres
([Pause to save money](docs/use.md#pause-to-save-money)).
Under load the resolvers autoscale on CPU, up to `RESOLVER_MAX_INSTANCES` (7, a cost cap that fits `STANDARD_L`'s connection budget), with the
pool adding nodes; one resolver CPU resolves roughly 35-40 records a second. Size Postgres
for a large first load (`STANDARD_XL` or larger) and back down after it. The app
checks every configuration against the pool's nodes and the Postgres connection budget.
See [Sizing](docs/use.md#sizing).

<sub><b>THE PATH</b></sub>

## The path

| # | Step | Where |
|---|---|---|
| 1 | Download the release and verify it | below |
| 2 | Run the infrastructure script | [install](docs/install.md#1-run-the-infrastructure-script) |
| 3 | Install: unpack, push the images, build the package, create the app | [install](docs/install.md#2-install-from-the-bundle) |
| 4 | Accept the Senzing EULA, the first step after the app exists | [install](docs/install.md#3-accept-the-senzing-eula) |
| 5 | Set the license secret | [install](docs/install.md#4-set-the-license-secret) |
| 6 | Run setup and start | [install](docs/install.md#5-run-setup-and-start) |
| 7 | Register a source | [use](docs/use.md#register-a-source) |
| 8 | Watch it resolve | [use](docs/use.md#watch-it-resolve) |
| 9 | Settings, upgrade, teardown | [use](docs/use.md) |

Prefer to have an AI assistant (Snowflake Cortex Code, Claude Code) run these steps and build a
report on your results? See [install and report with an AI assistant](docs/ai-assisted.md).

### No data of your own? Use the CORD data

`sz-snowflake-cord-data.tar.gz`, a file of every release, is the CORD data for the Senzing
Snowflake preview: Senzing's official [CORD](https://senzing.com/senzing-ready-data-collections-cord/) data (Collections Of Relatable Data,
real historical records published for evaluating entity resolution), from its Las Vegas
collection, reshaped into the normalized tables a data warehouse holds. Six source systems
(a CRM, a provider registry, a vendor master, a risk watchlist, a loan portfolio and a
legal-entity reference set) hold about 200,000 people and organizations. The original
JSONL is on the [CORD page](https://senzing.com/senzing-ready-data-collections-cord/). CORD is for evaluation only, not for operational use.

Verify it like the other files, load it with its `load.sql` (it creates the database
`SZ_CORD_DATA`, [install](docs/install.md#no-data-of-your-own-load-the-cord-data)), then
map each source system to Senzing and register it as a source
([use](docs/use.md#register-a-source)). The tables are not Senzing-ready: mapping them is
part of the exercise, and an AI assistant with the Senzing MCP tools can do it
([AI-assisted](docs/ai-assisted.md#no-data-of-your-own)).

<sub><b>VERIFY</b></sub>

## Verify

Everything a release carries is signed keyless as this repository's `sign-release`
workflow at that release's tag. The identity is exact, so an older release's signature
does not pass under a newer name.

```bash
sha256sum --ignore-missing -c SHA256SUMS   # the files you downloaded
IDENTITY="https://github.com/Senzing/sz-snowflake/.github/workflows/sign-release.yaml@refs/tags/<release>"
for f in SHA256SUMS sz-snowflake-<release>-linux-arm64.tar.gz sz-snowflake-infra-<release>.sql sz-snowflake-install-<release>.sh; do
  cosign verify-blob --bundle "$f.sigstore.json" \
    --certificate-identity "$IDENTITY" \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com "$f"
done
```

Add `sz-snowflake-cord-data.tar.gz` to the loop when you downloaded it. The signed bundle
contains the images, so verifying it verifies them. The install script
repeats these checks (`SHA256SUMS` and every signature, against the exact identity) before
it unpacks the bundle, and stops when one fails.

<sub><b>VERSIONING</b></sub>

## Versions

The Native App has one version per Senzing version (`V4_4_3`), and the build is its
patch (`ADD PATCH 7 FOR VERSION V4_4_3`, label `'4.4.3-7'`).

**During the Public Preview, any release can make breaking changes**, a patch within the
same Senzing version included: the app's procedures, functions, output tables, health
columns, service functions, settings and release files. Read the
[CHANGELOG](CHANGELOG.md) before you upgrade. Once out of preview, changes within a
Senzing version will be additive only, and breaking changes will come with the next
Senzing version, as a new app version.

<sub><b>LICENSE</b></sub>

## License

sz-snowflake is a Public Preview, provided as-is. The software is licensed under the
[Senzing End User License Agreement](https://senzing.com/end-user-license-agreement/).
Installing the Senzing packages in the images accepts it, and the app asks you to accept
it too before it runs anything: `SZ_SETUP` and `SZ_START` refuse until an `APP_ADMIN`
runs `CALL SZ_SNOWFLAKE.API.SZ_ACCEPT_EULA('I_ACCEPT_THE_SENZING_EULA')`
([install](docs/install.md#3-accept-the-senzing-eula)). More about Senzing:
[senzing.com](https://senzing.com).
