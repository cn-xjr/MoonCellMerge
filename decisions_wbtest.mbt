///|
test "template is usable for clean merges but never chooses conflicts" {
  let n = nb("")
  let r = merge(n, n, n)
  assert_eq(
    r.apply_decisions(canonical(r.decision_template())),
    r.resolve(Map([])),
  )
  let conflict = merge(
    nb(cell("a", "1")),
    nb(cell("a", "2")),
    nb(cell("a", "3")),
  )
  assert_true(
    try {
      let _ = conflict.apply_decisions(canonical(conflict.decision_template()))
      false
    } catch {
      _ => true
    },
  )
  let m = object(conflict.decision_template())
  m["choices"] = Json::object({ "/cells/a": Json::string("ours") })
  assert_eq(
    conflict.apply_decisions(canonical(Json::object(m))),
    conflict.resolve({ "/cells/a": Ours }),
  )
}

///|
test "decision API rejects stale exact inputs, duplicate keys and unknown fields" {
  let r = merge(nb(""), nb(""), nb(""))
  let m = object(r.decision_template())
  m["ignored"] = Json::null()
  assert_true(
    try {
      let _ = r.apply_decisions(canonical(Json::object(m)))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      let _ = r.apply_decisions("{\"review\":{},\"choices\":{},\"choices\":{}}")
      false
    } catch {
      _ => true
    },
  )
  let other = merge(nb("", meta="{\"new\":1}"), nb(""), nb(""))
  assert_true(
    try {
      let _ = other.apply_decisions(canonical(r.decision_template()))
      false
    } catch {
      _ => true
    },
  )
  assert_eq(
    r.apply_decisions(canonical(r.decision_template())),
    r.resolve(Map([])),
  )
}

///|
test "an explicit order resolves an order-only review with empty choices" {
  let a = cell("a", "a")
  let b = cell("b", "b")
  let r = merge(nb(a), nb(a + "," + b), nb(a + "," + cell("c", "c")))
  assert_eq(r.conflicts(), ["/cell-order"])
  let doc = object(r.decision_template())
  doc["order"] = Json::array(["a", "c", "b"].map(Json::string))
  let result = r.apply_decisions(canonical(Json::object(doc)))
  assert_eq(cells(read_notebook(result).value).map(id), ["a", "c", "b"])
  for legacy in ["base", "ours", "theirs"] {
    doc["choices"] = Json::object({ "/cell-order": Json::string(legacy) })
    assert_eq(r.apply_decisions(canonical(Json::object(doc))), result)
  }
  assert_true(r.to_text().contains("Set order to every retained cell ID"))
}

///|
test "custom order does not substitute for content choices or allow unknown choices" {
  let b = nb(cell("a", "before"))
  let r = merge(b, nb(""), nb(cell("a", "after")))
  let order = ["a"]
  for choices in [Map([]), { "/cells/a": Theirs, "/unknown": Ours }] {
    let accepted = try {
      let _ = r.resolve(choices, order~)
      true
    } catch {
      Invalid(_) => false
    }
    assert_false(accepted)
  }
  assert_eq(r.resolve({ "/cells/a": Ours }, order=[]), canonical(nb("").value))
  assert_eq(
    r.resolve({ "/cells/a": Theirs }, order~),
    canonical(nb(cell("a", "after")).value),
  )
}
