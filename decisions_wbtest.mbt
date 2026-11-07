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
