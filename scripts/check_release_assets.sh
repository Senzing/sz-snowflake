#!/usr/bin/env bash
# Verify a directory of release assets: what the build assembles (scripts/release_assets.sh),
# what the build uploads to the public release, and what the public workflow checks before it
# signs anything. The set is exact; anything else is refused, because the public workflow
# signs and publishes every file it finds.
#   scripts/check_release_assets.sh <dir> <release> [--bundle combined|per-arch] [--platforms linux/amd64,linux/arm64]
# Files: sz-snowflake-<release>.tar.gz (combined) or sz-snowflake-<release>-linux-<arch>.tar.gz
# per platform (per-arch), sz-snowflake-infra-<release>.sql, sz-snowflake-install-<release>.sh and
# SHA256SUMS, which must verify and list exactly the others. Each bundle is opened: its top
# directory, app/ (the app files), images/<arch>/sz-snowflake-<role>.tar for every role of
# every architecture it holds, and the infra SQL and install script, identical to the loose
# files. --bundle defaults to what the directory holds; --platforms to both architectures.
set -euo pipefail

dir=""; release=""; mode=""; platforms="linux/amd64,linux/arm64"
roles=(setup resolver replicator)
[ -f "$(dirname "$0")/../build.yaml" ] && read -r -a roles <<< "$("$(dirname "$0")/build_yaml.sh" roles)"
while [ $# -gt 0 ]; do
  case "$1" in
    --bundle) mode="${2:?--bundle needs a value}"; shift 2 ;;
    --platforms) platforms="${2:?--platforms needs a value}"; shift 2 ;;
    -*) echo "check_release_assets.sh: unknown option $1" >&2; exit 2 ;;
    *) if [ -z "$dir" ]; then dir="${1%/}"; elif [ -z "$release" ]; then release="$1"; else echo "check_release_assets.sh: too many arguments" >&2; exit 2; fi; shift ;;
  esac
done
if [ -z "$dir" ] || [ -z "$release" ]; then echo "usage: check_release_assets.sh <dir> <release> [--bundle combined|per-arch] [--platforms <list>]" >&2; exit 2; fi
[ -d "$dir" ] || { echo "check_release_assets.sh: $dir is not a directory" >&2; exit 1; }
[[ "$release" =~ ^[0-9]+\.[0-9]+\.[0-9]+-[1-9][0-9]*$ ]] || { echo "check_release_assets.sh: '$release' is not <senzing_version>-<build>" >&2; exit 1; }
archs=(); for p in ${platforms//,/ }; do archs+=("${p#linux/}"); done
if [ -z "$mode" ]; then
  if [ -f "$dir/sz-snowflake-$release.tar.gz" ]; then mode=combined; else mode=per-arch; fi
fi
case "$mode" in combined|per-arch) ;; *) echo "check_release_assets.sh: --bundle must be combined or per-arch" >&2; exit 2 ;; esac

fail=0
err() { echo "check_release_assets.sh: $*" >&2; fail=1; }

deliverables=()
if [ "$mode" = combined ]; then deliverables+=("sz-snowflake-$release.tar.gz")
else for a in "${archs[@]}"; do deliverables+=("sz-snowflake-$release-linux-$a.tar.gz"); done; fi
deliverables+=("sz-snowflake-infra-$release.sql" "sz-snowflake-install-$release.sh")

actual="$(find "$dir" -mindepth 1 -maxdepth 1 -exec basename {} \; | LC_ALL=C sort)"
expected="$(printf '%s\n' "${deliverables[@]}" SHA256SUMS | LC_ALL=C sort)"
[ "$actual" = "$expected" ] || err "$dir holds
$actual
but must hold exactly
$expected"
for f in "${deliverables[@]}"; do
  if [ ! -s "$dir/$f" ] || [ -L "$dir/$f" ]; then err "$f is missing, empty or a link"; fi
done

if [ -f "$dir/SHA256SUMS" ]; then
  listed="$(awk '{ print $2 }' "$dir/SHA256SUMS" | LC_ALL=C sort)"
  want="$(printf '%s\n' "${deliverables[@]}" | LC_ALL=C sort)"
  [ "$listed" = "$want" ] || err "SHA256SUMS lists
$listed
but must list exactly
$want"
  if command -v sha256sum >/dev/null; then sum=(sha256sum); else sum=(shasum -a 256); fi
  (cd "$dir" && "${sum[@]}" -c SHA256SUMS >/dev/null 2>&1) || err "SHA256SUMS does not verify"
fi

# Each bundle: one top directory with exactly the layout.
for f in "${deliverables[@]}"; do
  case "$f" in *.tar.gz) ;; *) continue ;; esac
  [ -s "$dir/$f" ] || continue
  name="${f%.tar.gz}"
  members="$(tar -tzf "$dir/$f" 2>/dev/null)" || { err "$f is not a readable tar.gz"; continue; }
  if [ "$mode" = combined ]; then bundle_archs=("${archs[@]}")
  else bundle_archs=("${name##*-linux-}"); fi
  need=("$name/app/manifest.yml" "$name/app/setup_script.sql" "$name/app/README.md" "$name/app/SHA256SUMS"
        "$name/app/services/setup.yaml" "$name/app/services/resolver.yaml" "$name/app/services/replicator.yaml"
        "$name/sz-snowflake-infra-$release.sql" "$name/sz-snowflake-install-$release.sh")
  for a in "${bundle_archs[@]}"; do
    for role in "${roles[@]}"; do need+=("$name/images/$a/sz-snowflake-$role.tar"); done
  done
  for m in "${need[@]}"; do
    grep -qxF "$m" <<< "$members" || err "$f lacks $m"
  done
  # nothing outside the layout (directory entries aside)
  while IFS= read -r m; do
    case "$m" in */) continue ;; esac
    printf '%s\n' "${need[@]}" | grep -qxF "$m" || err "$f carries the unexpected member $m"
  done <<< "$members"
done

[ "$fail" = 0 ] || exit 1
echo "release assets $release ($mode; ${archs[*]/#/linux/}; roles ${roles[*]}): ok"
