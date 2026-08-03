#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
formula="$repo_root/Formula/crlc.rb"

ruby -c "$formula"

if grep -nE 'gitlab\.com|contrl-group' "$formula" "$repo_root/README.md"; then
  echo "GitLab source or install URL remains in the active tap" >&2
  exit 1
fi

release_pairs=()
while IFS= read -r release_pair; do
  release_pairs+=("$release_pair")
done < <(
  ruby -e '
    formula = File.read(ARGV.fetch(0))
    pairs = formula.scan(/url "([^"]+)"\s+sha256 "([0-9a-f]{64})"/m)
    abort "expected four release URL/checksum pairs" unless pairs.length == 4
    pairs.each { |url, sha256| puts "#{url}\t#{sha256}" }
  ' "$formula"
)

download_dir=$(mktemp -d)
trap 'rm -rf "$download_dir"' EXIT

linux_amd64_archive=""
for release_pair in "${release_pairs[@]}"; do
  IFS=$'\t' read -r release_url expected_sha256 <<< "$release_pair"
  case "$release_url" in
    https://github.com/contrl-co/crl/releases/download/*) ;;
    *)
      echo "unexpected release host: $release_url" >&2
      exit 1
      ;;
  esac

  archive="$download_dir/${release_url##*/}"
  curl --fail --location --silent --show-error --retry 3 \
    --proto '=https' --tlsv1.2 "$release_url" --output "$archive"
  if command -v sha256sum >/dev/null 2>&1; then
    actual_sha256=$(sha256sum "$archive" | awk '{print $1}')
  else
    actual_sha256=$(shasum -a 256 "$archive" | awk '{print $1}')
  fi
  test "$actual_sha256" = "$expected_sha256"

  if [[ ${release_url##*/} == crlc_linux_amd64.tar.gz ]]; then
    linux_amd64_archive="$archive"
  fi
done

test -n "$linux_amd64_archive"
if [[ $(uname -s) == Linux && $(uname -m) == x86_64 ]]; then
  mkdir "$download_dir/linux-amd64"
  tar -xzf "$linux_amd64_archive" -C "$download_dir/linux-amd64"
  "$download_dir/linux-amd64/crlc" version | grep -F 'editions: v1'
fi
