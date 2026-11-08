///|
test "source edits merge nonoverlapping line replacements symmetrically" {
  let b = "a\r\nb\r\nc"
  let o = "A\r\nb\r\nc"
  let t = "a\r\nb\r\nC"
  assert_eq(compose_source(b, o, t), Some("A\r\nb\r\nC"))
  assert_eq(compose_source(b, o, t), compose_source(b, t, o))
  assert_eq(compose_source(b, o, b), Some(o))
  assert_eq(compose_source(b, o, o), Some(o))
  assert_eq(compose_source("a\nb\n", "A\nb\n", "a\nB\n"), Some("A\nB\n"))
}

///|
test "overlap insertion ambiguity and bounded complex spans require review" {
  assert_eq(compose_source("a\n", "ours\n", "theirs\n"), None)
  assert_eq(compose_source("a\nb\n", "x\na\nb\n", "y\na\nb\n"), None)
  assert_eq(compose_source("a\nb\nc\n", "A\nb\nC\n", "a\nB\nc\n"), None)
  assert_eq(
    compose_source("a\n".repeat(4001), "b\n".repeat(4001), "c\n".repeat(4001)),
    None,
  )
}

///|
test "same-cell source auto merge requires empty execution evidence" {
  fn n(s : String, outputs : String) -> Notebook raise MergeError {
    let v = object(nb(cell("a", "", outputs~)).value)
    guard v["cells"] is Array(a) && a[0] is Object(c) else {
      raise Invalid("shape")
    }
    c["source"] = Json::string(s)
    read_notebook(canonical(Json::object(v)))
  }
  let b = n("a\nb\nc\n", "[]")
  let o = n("A\nb\nc\n", "[]")
  let t = n("a\nb\nC\n", "[]")
  let r = merge(b, o, t)
  assert_eq(r.conflicts(), [])
  assert_eq(
    source(cells(read_notebook(r.resolve(Map([]))).value)[0]),
    "A\nb\nC\n",
  )
  assert_eq(
    restore_review(canonical(r.to_json())).resolve(Map([])),
    r.resolve(Map([])),
  )
  let evidence = "[{\"output_type\":\"stream\",\"name\":\"stdout\",\"text\":\"evidence\"}]"
  assert_eq(
    merge(
      n("a\nb\nc\n", evidence),
      n("A\nb\nc\n", evidence),
      n("a\nb\nC\n", evidence),
    ).conflicts(),
    ["/cells/a"],
  )
}
