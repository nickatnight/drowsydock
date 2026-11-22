#!/usr/bin/env bash
set -euo pipefail

if (($# != 3)); then
  echo "usage: scripts/ci/install-gitleaks.sh VERSION SHA256 DEST" >&2
  exit 2
fi
version="$1"
expected="$2"
dest="$3"

if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "install-gitleaks: VERSION must look like 8.30.1, got '$version'" >&2
  exit 2
fi
if [[ ! $expected =~ ^[0-9a-f]{64}$ ]]; then
  echo "install-gitleaks: SHA256 must be 64 lowercase hex digits, got '$expected'" >&2
  exit 2
fi

asset="gitleaks_${version}_darwin_arm64.tar.gz"
url="https://github.com/gitleaks/gitleaks/releases/download/v${version}/${asset}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
  --retry 3 --output "$work/$asset" "$url"

actual="$(shasum -a 256 "$work/$asset" | awk '{ print $1 }')"
if [[ $actual != "$expected" ]]; then
  echo "install-gitleaks: checksum mismatch for $asset" >&2
  echo "  expected $expected" >&2
  echo "  actual   $actual" >&2
  exit 1
fi

tar -xzf "$work/$asset" -C "$work" gitleaks
mkdir -p "$dest"
install -m 0755 "$work/gitleaks" "$dest/gitleaks"
echo "install-gitleaks: installed gitleaks $version ($actual) in $dest"
