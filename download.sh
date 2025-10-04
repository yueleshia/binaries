#!/bin/sh

#run: % yueleshia/binaries nonsemantic "zig-x86_64-linux-0.15.1.tar.xz" "tmp/zig" 10 "c61c5da6edeea14ca51ecd5e4520c6f4189ef5250383db33d01848293bfafe05"

owner_repo="${1}"
tag="${2}"
key="${3}"
out_initial="${4}"
dl_timeout="${5}"
sha256="${6}"

printf %s "Arguments: " >&2
printf " '%s'" "$@" >&2
printf \\n >&2

list_assets() {
  curl --silent \
    --location "https://api.github.com/repos/${owner_repo}/releases/tags/${tag}" \
    --header   "Accept: application/vnd.github.v3+json" \
    --header   "X-GitHub-Api-Version: 2022-11-28" \
  # end
}
mkdir_for_path() (
  dirname="$( dirname "${1}"; printf a )"
  mkdir -p "${dirname%?a}"
)

if true; then
  url="https://github.com/${owner_repo}/releases/download/${tag}/${key}"
  printf %s\\n "Downloading ${url}" >&2
  mkdir_for_path "${out_initial}"
  code="$( curl \
    --location        "${url}" \
    --connect-timeout "${dl_timeout}" \
    --write-out       "%{http_code}" \
    --output          "${out_initial}" \
  )" || {
    printf %s\\n "Failed to download: ${URL}" >&2
    exit 1
  }
  if [ 200 != "${code}" ]; then
    assets="$( list_assets | jq '.assets | map(.name) | sort' )"
    if ! $( printf %s\\n "${assets}" | jq --arg k "${key}" 'any(. == $k)' ); then
      printf %s\\n "Invalid key. Valid keys are:" >&2
      printf '%s\n' "${assets}" | jq --raw-output '"  " + join("\n  ")'
    else
      printf %s\\n "HTTP ERROR: ${code}" >&2
    fi
    exit 1
  fi
fi

printf %s\\n "=== Checking SHA256 hash ===" >&2
printf %s\\n "Go to https://github.com/yueleshia/binaries/blob/main/binaries.json to see hashes these were uploaded with"

hash="$( sha256sum "${out_initial}" )" || exit "$?"
if [ "${hash%% *}" != "${sha256}" ]; then
  printf %s\\n "Incorrect sha256. The file is not what you expected according to your hash" >&2
  printf %s\\n "  you specified:   ${sha256}" >&2
  printf %s\\n "  downloaded with: ${hash%% *}" >&2

  upload_sha="$( list_assets | jq --raw-output --arg k "${key}" '
    .assets | map(select(.name == $k).digest)[0]
  ' )" || exit "$?"
  printf %s\\n "This was uploaded with" >&2
  printf %s\\n "  uploaded:        ${upload_sha#sha256:}" >&2
  exit 1
else
  printf %s\\n "SHA256 of download is valid" >&2
fi
