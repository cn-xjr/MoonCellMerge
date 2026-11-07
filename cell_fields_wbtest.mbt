///|
fn metadata_cell(
  text : String,
  metadata : String,
  outputs~ : String = "[]",
) -> Notebook raise MergeError {
  nb(
    cell("a", text, outputs~).replace(
      old="\"metadata\":{}",
      new="\"metadata\":" + metadata,
    ),
  )
}

///|
test "same-cell source and metadata edits compose symmetrically" {
  let b = metadata_cell("1", "{\"tag\":\"old\"}")
  let o = metadata_cell("2", "{\"tag\":\"old\"}")
  let t = metadata_cell("1", "{\"tag\":\"new\"}")
  let r = merge(b, o, t)
  assert_eq(r.conflicts(), [])
  let text = r.resolve(Map([]))
  assert_true(text.contains("new") && text.contains("\"source\":\"2\""))
  assert_eq(text, merge(b, t, o).resolve(Map([])))
}

///|
test "independent metadata fields retain unknown values and explicit deletion" {
  let b = metadata_cell(
    "1", "{\"keep\":9007199254740993,\"drop\":1,\"change\":1}",
  )
  let o = metadata_cell("1", "{\"keep\":9007199254740993,\"change\":1}")
  let t = metadata_cell(
    "1", "{\"keep\":9007199254740993,\"drop\":1,\"change\":null}",
  )
  let text = merge(b, o, t).resolve(Map([]))
  assert_true(text.contains("9007199254740993"))
  assert_true(text.contains("\"change\":null"))
  assert_true(!text.contains("\"drop\""))
  let conflict = merge(
    metadata_cell("1", "{\"x\":1}"),
    metadata_cell("1", "{}"),
    metadata_cell("1", "{\"x\":null}"),
  )
  assert_eq(conflict.conflicts(), ["/cells/a"])
}

///|
test "source and competing execution evidence remain a whole-cell conflict" {
  let output = "[{\"output_type\":\"stream\",\"name\":\"stdout\",\"text\":\"evidence\"}]"
  let b = metadata_cell("1", "{}")
  let o = metadata_cell("2", "{}")
  let t = metadata_cell("1", "{}", outputs=output)
  let r = merge(b, o, t)
  assert_eq(r.conflicts(), ["/cells/a"])
  assert_eq(r.resolve({ "/cells/a": Ours }), canonical(o.value))
  let retained = merge(
    metadata_cell("1", "{}", outputs=output),
    metadata_cell("2", "{}", outputs=output),
    metadata_cell("1", "{\"tag\":1}", outputs=output),
  )
  assert_eq(retained.conflicts(), ["/cells/a"])
}
