///|
test "independent notebook metadata edits compose and replay" {
  let b = nb(
    "",
    meta="{\"kernelspec\":{\"name\":\"python3\"},\"owner\":\"team\"}",
  )
  let o = nb(
    "",
    meta="{\"kernelspec\":{\"name\":\"python3\"},\"owner\":\"new-team\"}",
  )
  let t = nb(
    "",
    meta="{\"kernelspec\":{\"name\":\"python3\"},\"owner\":\"team\",\"vendor\":9007199254740993}",
  )
  let r = merge(b, o, t)
  assert_eq(r.conflicts(), [])
  let text = r.resolve(Map([]))
  assert_true(text.contains("new-team") && text.contains("9007199254740993"))
  assert_eq(text, merge(b, t, o).resolve(Map([])))
  assert_eq(restore_review(canonical(r.to_json())).resolve(Map([])), text)
}

///|
test "metadata deletion and null are distinct and nested producers are atomic" {
  let b = nb("", meta="{\"delete\":1,\"other\":0}")
  let text = merge(
    b,
    nb("", meta="{\"other\":0}"),
    nb("", meta="{\"delete\":1,\"other\":null}"),
  ).resolve(Map([]))
  assert_true(!text.contains("delete") && text.contains("null"))
  let r = merge(
    nb("", meta="{\"producer\":{\"a\":1,\"b\":1}}"),
    nb("", meta="{\"producer\":{\"a\":2,\"b\":1}}"),
    nb("", meta="{\"producer\":{\"a\":1,\"b\":2}}"),
  )
  assert_eq(r.conflicts(), ["/notebook/metadata"])
  assert_true(
    try {
      let _ = r.resolve(Map([]))
      false
    } catch {
      _ => true
    },
  )
  assert_eq(merge(b, b, b).resolve(Map([])), canonical(b.value))
}
