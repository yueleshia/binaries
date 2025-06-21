let lib = import "cicd/_lib.ncl" in
(import "binaries.ncl") & {
  "will_fail_for_testing" = {
    key            = "will_fail",
    is_direct_dl   = true,
    url            = "%{lib.dl_url_prefix}will_fail",
    SHA256         = ""
  }
} | { _ | lib.BinaryDef }
