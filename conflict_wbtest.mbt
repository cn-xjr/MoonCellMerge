///|
test "conflict evidence distinguishes deleted fields from JSON null" {
  fn n(extra : String) -> Notebook raise MergeError {
    read_notebook(
      "{\"nbformat\":4,\"nbformat_minor\":5,\"metadata\":{},\"cells\":[]" +
      extra +
      "}",
    )
  }
  let r = merge(n(",\"x\":1"), n(""), n(",\"x\":null"))
  let c = r.details()[0]
  assert_eq(c.path, "/notebook/x")
  assert_eq(canonical(c.ours), "{\"present\":false}")
  assert_eq(canonical(c.theirs), "{\"value\":null,\"present\":true}")
  assert_true(r.to_text().contains("Select base/ours/theirs"))
}

///|
test "evidence mutations cannot change review inputs or replay" {
  let r = merge(nb(cell("a", "1")), nb(cell("a", "2")), nb(cell("a", "3")))
  let before = r.resolve({ "/cells/a": Ours })
  guard r.details()[0].ours is Object(m) && m["value"] is Object(c) else {
    fail("evidence shape")
  }
  c["source"] = Json::string("mutated")
  assert_eq(r.resolve({ "/cells/a": Ours }), before)
  assert_eq(restore_review(canonical(r.to_json())).to_text(), r.to_text())
}

///|
test "diagnostic paths escape terminal controls and show delete-edit evidence" {
  let r = merge(nb(cell("a", "1")), nb(""), nb(cell("a", "2")))
  assert_eq(r.details()[0].kind, "delete-edit")
  assert_true(r.to_text().contains("\"present\":false"))
  let m = object(nb("").value)
  m["\u001b[31m"] = Json::number(1)
  let b = read_notebook(canonical(Json::object(m)))
  m["\u001b[31m"] = Json::number(2)
  let o = read_notebook(canonical(Json::object(m)))
  m["\u001b[31m"] = Json::number(3)
  let text = merge(b, o, read_notebook(canonical(Json::object(m)))).to_text()
  assert_true(!text.contains("\u001b"))
}
