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

///|
test "public conflict reports include order requirements without the replay inputs" {
  fn with_ids(
    ids : Array[String],
  ) -> @mooncellmerge.Notebook raise @mooncellmerge.MergeError {
    let rows = ids.map(id => {
      "{\"id\":\"" +
      id +
      "\",\"cell_type\":\"raw\",\"metadata\":{},\"source\":\"\"}"
    })
    @mooncellmerge.read_notebook(
      "{\"nbformat\":4,\"nbformat_minor\":5,\"metadata\":{},\"cells\":[" +
      rows.join(",") +
      "]}",
    )
  }
  let b = with_ids(["a", "b"])
  let o = with_ids(["a", "ours", "b"])
  let t = with_ids(["a", "theirs", "b"])
  let clean = @mooncellmerge.merge(b, b, b)
  assert_eq(
    clean.conflict_report(),
    Json::object({
      "conflicts": Json::array([]),
      "requires_order": Json::boolean(false),
      "version": Json::number(1),
    }),
  )
  let report = @mooncellmerge.merge(b, o, t).conflict_report()
  guard report is Object(root) && root["conflicts"] is Array(items) else {
    fail("Expected conflict report")
  }
  assert_eq(root.get("requires_order"), Some(Json::boolean(true)))
  assert_eq(root.length(), 3)
  assert_eq(items.length(), 1)
  guard items[0] is Object(fields) else { fail("Expected order evidence") }
  assert_eq(fields.get("path"), Some(Json::string("/cell-order")))
  assert_eq(fields.get("kind"), Some(Json::string("cell-order")))
  assert_eq(
    fields["ours"],
    Json::object({
      "present": Json::boolean(true),
      "value": Json::array(["a", "ours", "b"].map(Json::string)),
    }),
  )
}
