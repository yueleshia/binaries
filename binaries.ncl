let lib = import "cicd/_lib.ncl" in

let manual_entry =  [
  {
    version        = "0.20.1",
    key            = "lychee-0.20.1",
    is_direct_dl   = true,
    url            = "https://github.com/lycheeverse/lychee/releases/download/lychee-v0.20.1/lychee-x86_64-unknown-linux-musl.tar.gz",
    SHA256         = "6c51e0245a738b7c6e46e47ff4da48c6b367bba1b55776f249673338ca9698a4",
  },
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
    SHA256         = "db67563922bb0d7ed2e438cd5ddb72c207625fb375a1dc91c058275af1a62ef4",
  },
  {
    version        = "0.15.1",
    key            = "zig-x86_64-linux-%{version}.tar.xz",
    name_default   = "zig-%{version}",
    is_direct_dl   = false,
    url            = "https://pkg.machengine.org/zig/zig-x86_64-linux-%{version}.tar.xz",
    SHA256         = "c61c5da6edeea14ca51ecd5e4520c6f4189ef5250383db33d01848293bfafe05",
    comment        = m%"
      Use the following step instead:

      - uses: mlugg/setup-zig@v2
        with:
          version: %{version}
          mirror:  %{lib.dl_url_prefix}
    "%,
  },
  {
    version        = "0.11.1",
    key            = "zine-0.11.1",
    is_direct_dl   = true,
    url            = "https://github.com/kristoff-it/zine/releases/download/v0.11.1/x86_64-linux-musl.tar.xz",
    SHA256         = "235e1a2d150ce34fe117665d5f05b41a373fc4082ad5f56b7baa908dc2608069",
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
