# sz-snowflake

Container build for Senzing on Snowflake.

This repository holds the `Dockerfile` for the Senzing-on-Snowflake evaluation
container and publishes it to `ghcr.io/senzing/sz-snowflake`.

The application payload is built elsewhere and arrives here as a release asset.
Each release on this repository carries
`sz-snowflake-payload-<version>.tar.gz` and its `.sha256`; publishing a release
is what triggers the image build. The build verifies the checksum, unpacks the
payload into the build context, and pushes a signed, attested image tagged with
the release's version. The release creates the tag at `main` as it stood at
that moment rather than at a nominated commit; the commit the image was
actually built from is recorded in its build provenance attestation.
