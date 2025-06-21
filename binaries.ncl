let lib = import "cicd/_lib.ncl" in

let manual_entry =  [
  {
    version        = "1.12.0",
    key            = "nickel-%{version}",
    is_direct_dl   = true,
    url            = "https://github.com/tweag/nickel/releases/download/%{version}/nickel-x86_64-linux",
    SHA256         = "511b06bc96e30c9cc7ec1fd5467e63477b274cc905f26824c54773ae76666eb4",
  },
  {
    key            = "tetra",
    is_direct_dl   = true,
    url            = "",
    SHA256         = "7e3e5884120d3be1a6e25aed2ed680575f8f4f084aabe602a3239d726b4269df",
  },
  {
    version        = "0.14.1",
    key            = "zig-x86_64-linux-%{version}.tar.xz",
    name_default   = "zig-%{version}",
    is_direct_dl   = false,
    url            = "https://pkg.machengine.org/zig/zig-x86_64-linux-%{version}.tar.xz",
    SHA256         = "24aeeec8af16c381934a6cd7d95c807a8cb2cf7df9fa40d359aa884195c4716c",
    comment        = m%"
      Use the following step instead:

      - uses: mlugg/setup-zig@v2
        with:
          version: %{version}
          mirror:  %{lib.dl_url_prefix}
    "%,
  },
] | Array lib.BinaryDef in

manual_entry
|> std.array.map (fun v => {
  field = v.key,
  value =
    let out = v & { name_default | default = v.key } in

    if out.is_direct_dl then
      out
    else if out.comment == "" then
      std.fail_with "Please provide a comment for '%{v.key}' because it cannot use the default action as is_direct_dl is false"
    else (
      out
    )
  ,
})
|> std.record.from_array
