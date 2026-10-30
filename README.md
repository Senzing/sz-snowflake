<p>
  <img src="assets/senzing-logo.jpg" alt="Senzing" width="48" align="left" hspace="8">
  <samp><b>SENZING</b></samp>
</p>
<br clear="left">

# sz-snowflake

**Entity resolution inside your own Snowflake account. Senzing hosts nothing and receives nothing.**

Senzing entity resolution as a Snowflake Native App that you build and install
yourself, running on Snowpark Container Services with Snowflake Postgres as the
Senzing repository. Each release is **one download**: a signed bundle holding the app
files and the three container images, which you push to your own Snowflake image
repository. No source code is published, and nothing is pulled from a public registry.

This page is the guide. The steps are in [docs/install.md](docs/install.md), day-to-day
use in [docs/use.md](docs/use.md), and what to do when something fails in
[docs/troubleshooting.md](docs/troubleshooting.md).

<sub><b>RELEASE ASSETS</b></sub>

## What a release contains

| Asset | Content |
|---|---|
| `sz-snowflake-<release>.tar.gz` | the bundle, both architectures: `app/` (the Native App files: `manifest.yml`, `setup_script.sql`, `services/*.yaml`, `README.md`, `SHA256SUMS`), `images/<arch>/sz-snowflake-<role>.tar` (the three images for `amd64` and `arm64`, as docker archives), the infrastructure script and the install script |
| `sz-snowflake-infra-<release>.sql` | the infrastructure script you run and own (Postgres instance, network rules, policy, integration, secrets), also on its own so you can read it before downloading the bundle |
| `sz-snowflake-install-<release>.sh` | the package build and install steps, each printed before it runs |
| `SHA256SUMS`, `*.sigstore.json` | checksums, and a keyless cosign signature for every file above |

Some releases may instead carry one bundle per architecture,
`sz-snowflake-<release>-linux-<arch>.tar.gz`; the steps are the same.

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
| A Senzing license (base64) | optional; without one the engine stops at 500 records. Never put it in a committed file |
| One release's files | download the bundle, `SHA256SUMS` and the `*.sigstore.json` files from this repository's [releases](https://github.com/Senzing/sz-snowflake/releases) |

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

<sub><b>VERIFY</b></sub>

## Verify

Everything a release carries is signed keyless as this repository's `sign-release`
workflow at that release's tag. The identity is exact, so an older release's signature
does not pass under a newer name.

```bash
sha256sum -c SHA256SUMS
IDENTITY="https://github.com/Senzing/sz-snowflake/.github/workflows/sign-release.yaml@refs/tags/<release>"
for f in SHA256SUMS sz-snowflake-<release>.tar.gz sz-snowflake-infra-<release>.sql sz-snowflake-install-<release>.sh; do
  cosign verify-blob --bundle "$f.sigstore.json" \
    --certificate-identity "$IDENTITY" \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com "$f"
done
```

The signed bundle contains the images, so verifying it verifies them. The install script
repeats these checks (`SHA256SUMS` and every signature, against the exact identity) before
it unpacks the bundle, and stops when one fails.

<sub><b>VERSIONING</b></sub>

## Versions

The Native App has one version per Senzing version (`V4_4_3`), and the build is its
patch (`ADD PATCH 7 FOR VERSION V4_4_3`, label `'4.4.3-7'`). Within a Senzing version
the app's procedures, functions, output tables, health columns and service functions
change only additively; breaking changes come with the next Senzing version, as a new
app version.

<sub><b>LICENSE</b></sub>

## License

The software is licensed under the
[Senzing End User License Agreement](https://senzing.com/end-user-license-agreement/).
Installing the Senzing packages in the images accepts it, and the app asks you to accept
it too before it runs anything: `SZ_SETUP` and `SZ_START` refuse until an `APP_ADMIN`
runs `CALL SZ_SNOWFLAKE.API.SZ_ACCEPT_EULA('I_ACCEPT_THE_SENZING_EULA')`
([install](docs/install.md#3-accept-the-senzing-eula)). More about Senzing:
[senzing.com](https://senzing.com).
