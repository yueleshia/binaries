{
  dl_url_prefix = "https://github.com/yueleshia/binaries/releases/download/nonsemantic/",

  BinaryDef | not_exported = {
    key            | String,
    version        | String | optional,
    name_default   | String | optional,
    is_direct_dl   | Bool,
    url            | String,
    SHA256         | String,
    comment        | String | default = "",
  },

  GitHubMatrix | not_exported = {
    _ | std.contract.Sequence [Array Dyn, std.array.NonEmpty]
  },

  format_inputs
    | not_exported
    | {
      _ | {
        required     | Bool,
        description | String | optional,
        type        | [| 'boolean, 'choice, 'number, 'string |],
        "default"   | Dyn | optional,
        options     | Array String | optional,
      }
    } -> Dyn
    = fun input_map => {
      composite         = input_map,
      workflow_dispatch = input_map,
      workflow_call     = input_map
        |> std.record.map_values (fun x =>
          if x.type == 'choice
          then x |> std.record.update "type" "string" |> std.record.remove "options"
          else x
        )
      ,
      use   = input_map |> std.record.map (fun k v => "${{ inputs.%{k} }}"),
      embed = input_map |> std.record.map (fun k v => "inputs.%{k}"),
    }
  ,
}
