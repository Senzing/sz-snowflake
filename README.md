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

## Cutting a release

**Create the release as a draft, attach the assets, and publish it last.**
The image build triggers on `release: published`, so a release that is
published before its assets are attached starts a build that has nothing to
download. The build waits a few minutes for the assets to appear and then
fails.

A release must carry exactly one `sz-snowflake-payload-<version>.tar.gz` and
exactly one matching `.sha256`. The checksum is verified before the payload is
unpacked; because both assets come from the same release, that is integrity
against a bad download rather than proof of where the payload was built.

The `.sha256` must **name the tarball, by its basename alone**. The build runs
`sha256sum --check` from the directory it downloaded the assets into, so a
line carrying a path -- `<hex>  dist/sz-snowflake-payload-1.0.0.tar.gz` --
fails on a file that is not there, and a file holding only a bare digest is
rejected outright as having no properly formatted checksum line. Running
`sha256sum` on the tarball from the directory that holds it produces the right
thing, and so does `openssl dgst -r -sha256`. Plain `openssl dgst -sha256`
does not: OpenSSL 3 writes `SHA2-256(file)= <hex>`, which GNU
`sha256sum --check` rejects outright as having no properly formatted checksum
line. The BSD-style `SHA256 (file) = <hex>` and the OpenSSL 1.x
`SHA256(file)= <hex>` both read correctly.

The tag must be bare semver -- `1.0.0`, with no `v` prefix, no leading zeros
and no pre-release suffix -- because it becomes the image tag. The release
must also not be marked **Set as a pre-release**: that is a checkbox rather
than part of the tag, so it passes every test the tag string can make, and it
is rejected for the same reason a `-rc1` suffix is -- the `:latest` ordering
excludes pre-releases, so such an image could never take `:latest`. Publishing
a version that already exists in the registry is refused.

## `:latest`

`:latest` is pushed only when the release being published is the highest
published version on this repository, so releasing a patch on an older line
does not move it backwards.

A build that fails **before** the image is pushed leaves nothing behind and
can be re-run from the release. A build that fails **after** the push --
signing, attestation, verification or the notification step, which is where
the shared action's own failures live -- cannot: the version is in the
registry, so re-running hits the immutability refusal, and no later release
repairs `:latest`, because a release on a lower line declines it too.

Recover by running the **Docker build and publish** workflow manually from the
Actions tab. It builds and pushes nothing; it copies the manifest of the
highest published version onto `:latest` inside the registry. It takes no
input, so it cannot be pointed at an arbitrary image, and running it when
nothing is wrong does nothing.
