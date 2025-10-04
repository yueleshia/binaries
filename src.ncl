let lib = import "cicd/_lib.ncl" in
let bin = import "binaries.json" as 'Json in

# run: nickel export % --field script --format raw | BASE=".." KEY="zig-x86_64-linux-0.14.1.tar.xz" sh -
#run: nickel export % --field pipeline --format yaml | tee action.yaml

{
  files = {
  },

  inp = lib.format_inputs {
    key  = {
      description = "Name in releases to download",
      type        = 'choice,
      required    = true,
      options     =
        bin
        |> std.record.filter (fun k v => v.is_direct_dl)
        |> std.record.fields
      ,
    },
    owner_repo = {
      description = "Owner/Repo",
      type        = 'string,
      required    = false,
      "default"   = "yueleshia/binaries",
    },
    release_tag = {
      description = "Owner/Repo",
      type        = 'string,
      required    = false,
      "default"   = "nonsemantic",
    },
    name = {
      description = "Name to rename the downloaded binary, not used if downloading an archive",
      type        = 'string,
      required    = false,
    },
    sha256 = {
      description = "The SHA256 to validate the binary",
      type        = 'string,
      required    = true,
    },
    timeout = {
      description = "Max seconds for download",
      type        = 'number,
      required    = false,
      default     = 120,
    },
  },
  output = {},

  pipeline = {
    name     = "Download binary",
    #run-name = name,

    inputs = inp.workflow_call,
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
          name  = "Download %{inp.use.key}",
          shell = "bash",
          env   = {
            key         = inp.use.key,
            name        = inp.use.name,
            sha256      = inp.use.sha256,
            timeout     = inp.use.timeout,

            owner_repo  = inp.use.owner_repo,
            release_tag = inp.use.release_tag,
            action_path = "${{ github.action_path }}",
            bin_dir     = "${{ github.workspace }}/bin",
            tmp_dir     = "${{ runner.temp }}",
          },
          run   = m%"
            mkdir -p "${bin_dir}"
            dl() {
              "${action_path}/download.sh" "${owner_repo}" "${release_tag}" "${key}" "${1}" "${timeout}" "${sha256}"
            }

            case "${key}"
            in *'.tar.gz'|*'.tar.gzip'|*'.tar.xz')
              dl "${tmp_dir}/${key}" || exit "$?"
              printf %s\\n "Decompressing '${tmp_dir}/${key}' -> '${bin}/'" >&2
              tar -xvf "${tmp_dir}/${key}" -C "${bin_dir}/" || exit "$?"
              if [ "${name}" != "" ] && [ "${key}" != "${name}" ]; then
                printf %s\\n "Skipping rename because we extracted with tar" >&2
              fi
            ;; *)
              dl "${bin_dir}/${key}" || exit "$?"
              chmod +x "${bin_dir}/${key}" || exit "$?"
              if [ "${name}" != "" ] && [ "${key}" != "${name}" ]; then
                printf %s\\n "Renaming ${key} -> ${name}" >&2
                mv "${bin_dir}/${key}" "${bin_dir}/${name}" || exit "$?"
              fi
            esac

            tree -L 2 "${bin_dir}"
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
