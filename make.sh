#!/bin/sh

# `printf a` to prevent `$()` from striping trailing newline
wd="$( dirname "${0}"; printf a )"; wd="${wd%?a}"
cd "${wd}" || exit "$?"

# run: echo zig-x86_64-linux-0.14.1.tar.xz | % download
# run: echo will_fail | % download
#run: echo tetra | % download
# run: % "actions"

owner_repo="yueleshia/binaries"

make() {
  case "${1}"
  in orchestrate)
    hello="$( list | jq 'map(tojson) | join("\n")' )" || exit "$?"

    printf %s\\n "${hello}" | me="${0}" parallel --will-cite '
      name="$(   printf %s {} | jq --raw-output ".name" )" || exit "$?"
      url="$(    printf %s {} | jq --raw-output ".url" )" || exit "$?"
      sha256="$( printf %s {} | jq --raw-output ".sha256" )" || exit "$?"

      printf %s\\n "=== ${name} ===" >&2
      printf %s\\n "${name}" | "${me}" parse
      #curl \
      #  --location "${url}" \
      #  --output   "output/${url##*/}" \
      #>&2
      # end

    '
  ;; download)
    printf %s "Reading target from stdin, stripping newlines: " >&2
    key="$( cat - )" || exit "$?"
    printf %s\\n "'${key}'" >&2

    mkdir -p "tmp"

    entry="$( list | jq --raw-output --arg key "${key}" '.
      | map(select(.key == $key))
      | .[0] // error("Could not find \"" + $key + "\"")
    ' )" || exit "$?"

    sha256="$(  printf %s "${entry}" | jq --raw-output ".SHA256" )" || exit "$?"

    printf %s\\n "Query SHA256 from GitHub API..." >&2
    release="$( gh api /repos/${owner_repo}/releases/tags/nonsemantic )" || exit "$?"

    sha256_remote="$( printf %s\\n "${release}" | jq --raw-output --arg key "${key}" '
      .assets
      | map(select(.name == $key))
      | try .[0].digest // error("\n\nERROR: \"\($key)\" not uploaded")
      | ltrimstr("sha256:")
    ' )"
    if [ 0 != "$?" ]; then
      if [ "will_fail" = "${key}" ]; then
        printf %s\\n "Skipping download for will_fail (reserved for testing)" >&2
        exit 1
      fi
    elif [ "${sha256}" = "${sha256_remote}" ]; then
      printf %s\\n "Skipping upload because the SHA256's match: ${sha256}"
      exit 0
    else
      printf %s\\n "The SHA256's do match, deleting old for reupload" >&2
      printf %s\\n "  expected: sha256:${sha256}"
      printf %s\\n "  received: sha256:${sha256_remote}"
      gh release delete-asset nonsemantic "${key}"
    fi

    url="$( printf %s\\n "${entry}" | jq --raw-output '.url' )" || exit "$?"
    if [ "" = "${url}" ]; then
      printf %s\\n "Skipping download because no URL is configured" >&2
    else
      printf %s\\n "" "Downloading: ${url}" >&2
      code="$( curl  \
        --location  "${url}" \
        --output    "tmp/${key}" \
        --write-out "%{http_code}" \
      )" || exit "$?"

      if [ 200 != "${code}" ]; then
        printf %s\\n "Curl failed with HTTP code ${code}" >&2
        exit 1
      fi
    fi

    x="$( sha256sum "tmp/${key}" )"
    sha256_local="${x%% *}"
    if [ "${sha256}" != "${sha256_local%%}" ]; then
      printf %s\\n "" "Please update SHA256 for ${key}:" >&2
      printf %s\\n "  calculated: sha256:${sha256_local}" >&2
      printf %s\\n "  on-file:    sha256:${sha256}" >&2
      exit 1
    fi

    gh release upload nonsemantic "tmp/${key}"

  ;; actions)
    file="cicd/_output.ncl"
    printf %s "(import \"${file}\") |> std.record.fields" | nickel export

  ;; *)  printf %s\\n "ERROR: Invalid command: \`$*\`" >&2; exit 1
  esac
}

list() {
   nickel export binaries_test.ncl
 }

if [ "$*" = "" ]; then
  make "orchestrate"
else
  for cmd in "$@"; do
    make "${cmd}" || exit "$?"
  done
fi
