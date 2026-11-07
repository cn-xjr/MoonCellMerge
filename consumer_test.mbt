///|
test "public consumer roundtrip and conflict array ownership" {
  let text = "{\"nbformat\":4,\"nbformat_minor\":5,\"metadata\":{},\"cells\":[]}"
  let n = @mooncellmerge.read_notebook(text)
  let r = @mooncellmerge.merge(n, n, n)
  let external = r.conflicts()
  external.push("cannot mutate review")
  assert_eq(r.conflicts(), [])
  let restored = @mooncellmerge.restore_review(
    @mooncellmerge.canonical(r.to_json()),
  )
  assert_eq(restored.resolve(Map([])), r.resolve(Map([])))
}
