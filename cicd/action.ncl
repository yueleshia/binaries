let lib = import "_lib.ncl" in
let bin = import "../binaries.ncl" in

# run: nickel export % --field script --format raw | BASE=".." KEY="zig-x86_64-linux-0.14.1.tar.xz" sh -
#run: nickel export % --field pipeline --format yaml | tee ../action.yaml

{
  script = m%"
    KEY="${KEY}"
    SHA256="${HASH}"

    BASE="${BASE:-.}"
    TIMEOUT="${TIMEOUT:-120}"

    list="$( <<EOF jq .
    %{
      bin
      |> std.record.map_values (fun x =>
        x |> std.record.filter (fun k v => k == "is_direct_dl" || k == "SHA256" || k == "comment")
      )
      |> std.serialize 'Json
    }
    EOF
    )" || exit "$?"
    if ! entry="$( printf %s\\n "${list}" | jq --raw-output --arg key "${KEY}" '
      try .[$key] // error("\n\nERROR: \"" + $key + "\" is no longer hosted")
    ' )"; then
      printf %s\\n "The following are hosted:" >&2
      printf %s "${list}" | jq --raw-output 'keys | map("  - " + .) | join("\n")' >&2
      exit 1
    fi

    if [ false = "$( printf %s\\n "${entry}" | jq '.is_direct_dl' )" ]; then
      printf %s\\n "You cannot use this action to download ${KEY}" >&2
      printf %s\\n "${entry}" | jq --raw-output '.comment' >&2
      exit 1
    fi

    [ -z "${FILE}" ] || { printf %s\\n "Pass KEY to download via environment variables." >&2; exit 1; }

    mkdir -p "${BASE}/bin"
    sha256="$( printf %s "${json}" | jq --raw-output --arg key "${KEY}" '.[$key].sha256' )" || exit "$?"

    url="%{lib.dl_url_prefix}${KEY}"
    out="${BASE}/bin/${KEY}"
    printf %s\\n "Downloading ${url}" >&2
    code="$( curl \
      --connect-timeout "${TIMEOUT}" \
      --location        "${url}" \
      --output          "${out}" \
      --write-out       "%{"%"}{http_code}" \
    )" || {
      printf %s\\n "Failed to download: ${URL}" >&2
      exit 1
    }
    if [ 200 != "${code}" ]; then
      printf %s\\n "HTTP ERROR: ${code}" >&2
      exit 1
    fi

    printf %s\\n "=== Checking SHA256 hash ===" >&2
    printf %s\\n "Go to https://github.com/yueleshia/binaries/blob/main/binaries.json to see hashes these were uploaded with"

    hash="$( sha256sum "${out}" )" || exit "$?"
    if [ "${hash%% *}" != "${SHA256}" ]; then
      printf %s\\n "Incorrect sha256. The file is not what you expected according to your hash" >&2
      printf %s\\n "  expected: ${SHA256}" >&2
      printf %s\\n "  received: ${hash%% *}" >&2
      printf %s\\n "This was uploaded with" >&2
      printf %s\\n "  uploaded: $( printf %s "${entry}" | jq --raw-output '.SHA256' )" >&2
    fi

    chmod +x "${out}" || exit "$?"
  "%,
  files = {
  },

  input_defs = lib.format_inputs {
    key  = {
      description = "Rename the downloaded binary to the following",
      type        = 'choice,
      required    = true,
      options     =
        bin
        |> std.record.filter (fun k v => v.is_direct_dl)
        |> std.record.fields
      ,
    },
    name = {
      description = "Rename the downloaded binary to the following",
      type        = 'string,
      required    = true,
    },
    sha256 = {
      description = "Rename the downloaded binary to the following",
      type        = 'string,
      required    = true,
    },
    timeout = {
      description = "Rename the downloaded binary to the following",
      type        = 'string,
      required    = false,
      default     = "120",
    },
  },
  output = {},

  pipeline = {
    name     = "Download binary",
    #run-name = name,

    inputs = input_defs.workflow_call,
    runs = {
      using = "composite",
      steps = [
        {
          name  = "DEBUG - Workflow inputs",
          shell = "bash",
          run   = m%"
            # Quoting HEREDOC to prevent script injection
            <<'EOF' cat - >&2
            ${{ ToJSON(inputs) }}
            EOF
          "%,
        },
        {
          name  = "Download %{input_defs.use.key}",
          shell = "bash",
          env   = {
            BASE    = "${{ github.workspace }}",
            KEY     = input_defs.use.key,
            SHA256  = input_defs.use.sha256,
            TIMEOUT = input_defs.use.timeout,
          },
          run   = script,
        },
        {
          name  = "Renaming '%{input_defs.use.key}' -> '%{input_defs.use.name}'",
          shell = "bash",
          env   = {
            from = "${{ github.workspace }}/bin/%{input_defs.use.key}",
            into = "${{ github.workspace }}/bin/%{input_defs.use.name}",
          },
          run   = m%"
            [ "${from}" != "${into}" ] && mv "${from}" "${into}"
            tree -L 2 ${{ github.workspace }}""
          "%,
        },
        {
          name  = "Adding 'bin' to $PATH",
          shell = "bash",
          env   = { bin_dir = "${{ github.workspace }}/bin" },
          run   = m%"
            while [ "" != "${p}" ]; do
              x="${p%%:*}"
              p="${p#"${x}"}"
              p="${p#:}"

              if [ "${x}" = "${bin_dir}" ]; then
                printf %s\\n "Found ${bin_dir} in \$PATH, skipping modifying \$PATH" >&2
                exit 0
              fi
            done

            printf %s\\n "PATH=${PATH}:${bin_dir}" >>"${GITHUB_ENV}"
            printf %s\\n "Added ${bin_dir} to \$PATH" "  ${PATH}" >&2
          "%,
        }
      ],
    },
  }
}
