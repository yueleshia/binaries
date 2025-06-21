{
  ".github/workflows/action.yaml" = import "action.ncl",
} | {
  _ | {
    files    | { _ | String },
    script   | String | optional,
    inputs   | Dyn,
    output   | Dyn,
    pipeline | Dyn,
  }
}
