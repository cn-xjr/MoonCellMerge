///|
fn nb(c : String, meta~ : String = "{}") -> Notebook raise MergeError {
  read_notebook(
    "{\"nbformat\":4,\"nbformat_minor\":5,\"metadata\":" +
    meta +
    ",\"cells\":[" +
    c +
    "]}",
  )
}

///|
fn cell(key : String, text : String, outputs~ : String = "[]") -> String {
  "{\"id\":\"" +
  key +
  "\",\"cell_type\":\"code\",\"source\":\"" +
  text +
  "\",\"metadata\":{},\"execution_count\":null,\"outputs\":" +
  outputs +
  "}"
}

///|
test "independent cells, symmetry, identity, stable output" {
  let b = nb(cell("a", "1") + "," + cell("b", "2"))
  let o = nb(cell("a", "3") + "," + cell("b", "2"))
  let t = nb(cell("a", "1") + "," + cell("b", "4"))
  let r = merge(b, o, t)
  assert_eq(r.conflicts(), [])
  let result = r.resolve(Map([]))
  assert_eq(result, merge(b, t, o).resolve(Map([])))
  assert_eq(source(cells(read_notebook(result).value)[0]), "3")
  assert_eq(source(cells(read_notebook(result).value)[1]), "4")
  assert_eq(merge(b, o, b).resolve(Map([])), canonical(o.value))
  assert_eq(merge(b, o, o).resolve(Map([])), canonical(o.value))
}

///|
test "conflict decisions and review roundtrip" {
  let r = merge(nb(cell("a", "1")), nb(cell("a", "2")), nb(cell("a", "3")))
  assert_eq(r.conflicts(), ["/cells/a"])
  let saved = canonical(r.to_json())
  let restored = restore_review(saved)
  assert_eq(canonical(restored.to_json()), saved)
  assert_true(
    try {
      let _ = restored.resolve(Map([]))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      let _ = restored.resolve({ "/wrong": Ours })
      false
    } catch {
      _ => true
    },
  )
  assert_true(restored.resolve({ "/cells/a": Theirs }).contains("3"))
}

///|
test "duplicate IDs, missing IDs, duplicate JSON keys, malformed and recovery" {
  assert_true(
    try {
      let _ = nb(cell("a", "1") + "," + cell("a", "2"))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      let _ = nb("{\"cell_type\":\"raw\",\"source\":\"\",\"metadata\":{}}")
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      let _ = read_notebook("{\"nbformat\":4,\"nbformat\":4}")
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      let _ = read_notebook("{")
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      let _ = nb(cell("bad/id", ""))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      let _ = nb(
        "{\"id\":\"x\",\"cell_type\":\"future\",\"source\":\"\",\"metadata\":{}}",
      )
      false
    } catch {
      _ => true
    },
  )
  assert_eq(
    merge(nb(""), nb(""), nb("")).resolve(Map([])),
    canonical(nb("").value),
  )
}

///|
test "exact large metadata numbers and unknown fields survive" {
  let b = nb(
    cell("a", ""),
    meta="{\"vendor\":9007199254740993,\"decimal\":1.234567890123456789}",
  )
  let text = merge(b, b, b).resolve(Map([]))
  assert_true(text.contains("9007199254740993"))
  assert_true(text.contains("1.234567890123456789"))
  let t = nb(cell("a", ""), meta="{\"vendor\":9007199254740992}")
  assert_eq(merge(b, t, b).resolve(Map([])), canonical(t.value))
}

///|
test "source change with output requires acknowledgment, never cleared" {
  let output = "[{\"output_type\":\"stream\",\"name\":\"stdout\",\"text\":\"old result\"}]"
  let b = nb(cell("a", "1", outputs=output))
  let o = nb(cell("a", "2", outputs=output))
  let r = merge(b, o, b)
  assert_eq(r.conflicts(), ["/cells/a"])
  assert_true(r.resolve({ "/cells/a": Ours }).contains("old result"))
}

///|
test "delete versus edit retains evidence and explicit order" {
  let b = nb(cell("a", "1"))
  let r = merge(b, nb(""), nb(cell("a", "2")))
  assert_eq(r.conflicts(), ["/cells/a", "/cell-order"])
  assert_true(
    try {
      let _ = r.resolve({ "/cells/a": Theirs, "/cell-order": Theirs }, order=[])
      false
    } catch {
      _ => true
    },
  )
  let result = r.resolve({ "/cells/a": Theirs, "/cell-order": Theirs }, order=[
    "a",
  ])
  assert_eq(cells(read_notebook(result).value).length(), 1)
}

///|
test "simultaneous insertions require explicit nonlossy ordering" {
  let r = merge(nb(""), nb(cell("a", "1")), nb(cell("b", "2")))
  assert_eq(r.conflicts(), ["/cell-order"])
  assert_true(
    try {
      let _ = r.resolve({ "/cell-order": Ours })
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      let _ = r.resolve({ "/cell-order": Ours }, order=["a", "a"])
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      let _ = r.resolve({ "/cell-order": Ours }, order=["a", "missing"])
      false
    } catch {
      _ => true
    },
  )
  assert_eq(
    cells(
      read_notebook(r.resolve({ "/cell-order": Ours }, order=["b", "a"])).value,
    ).map(id),
    ["b", "a"],
  )
}

///|
test "one-sided cell move and source string array" {
  let a = cell("a", "1")
  let b = cell("b", "2")
  let base = nb(a + "," + b)
  let moved = nb(b + "," + a)
  assert_eq(merge(base, moved, base).resolve(Map([])), canonical(moved.value))
  let multi = nb(
    "{\"id\":\"m\",\"cell_type\":\"markdown\",\"source\":[\"a\",\"b\"],\"metadata\":{},\"attachments\":{\"x\":{\"image/png\":\"AA==\"}}}",
  )
  assert_eq(source(cells(multi.value)[0]), "ab")
  assert_true(merge(multi, multi, multi).resolve(Map([])).contains("AA=="))
}

///|
test "review tampering rejected and limit boundaries" {
  let r = merge(nb(""), nb(""), nb(""))
  let m = object(r.to_json())
  m["conflicts"] = Json::array([Json::string("fake")])
  assert_true(
    try {
      let _ = restore_review(canonical(Json::object(m)))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      let _ = nb(cell("a".repeat(65), ""))
      false
    } catch {
      _ => true
    },
  )
  let accepted = nb(cell("a".repeat(64), ""))
  assert_eq(merge(accepted, accepted, accepted).conflicts(), [])
}

///|
test "opaque notebook keys cannot collide with order conflict namespace" {
  fn extended(value : String) -> Notebook raise MergeError {
    read_notebook(
      "{\"nbformat\":4,\"nbformat_minor\":5,\"metadata\":{},\"cells\":[],\"cell-order\":" +
      value +
      ",\"a//~~\":" +
      value +
      "}",
    )
  }
  let r = merge(extended("1"), extended("2"), extended("3"))
  assert_eq(r.conflicts(), ["/notebook/a~1~1~0~0", "/notebook/cell-order"])
  let output = r.resolve({
    "/notebook/a~1~1~0~0": Theirs,
    "/notebook/cell-order": Ours,
  })
  assert_true(output.contains("\"cell-order\":2"))
  assert_true(output.contains("\"a//~~\":3"))
}
