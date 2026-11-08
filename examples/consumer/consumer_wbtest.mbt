///|
fn notebook(source : String, metadata : String) -> @cells.Notebook raise {
  let raw = "{\"nbformat\":4,\"nbformat_minor\":5,\"metadata\":"+metadata+",\"cells\":[{\"id\":\"a\",\"cell_type\":\"markdown\",\"metadata\":{},\"source\":\""+source+"\"}]}"
  @cells.read_notebook(raw)
}

///|
test "public source and notebook metadata composition with exact numbers" {
  let b = notebook("a\\nb\\nc\\n","{\"keep\":9007199254740993}")
  let o = notebook("A\\nb\\nc\\n","{\"keep\":9007199254740993}")
  let t = notebook("a\\nb\\nC\\n","{\"keep\":9007199254740993,\"producer\":\"consumer\"}")
  let r = @cells.merge(b,o,t)
  assert_eq(r.conflicts(),[])
  let output = r.resolve(Map([]))
  assert_true(output.contains("9007199254740993") && output.contains("consumer"))
  assert_true(output.contains("A\\nb\\nC\\n"))
}

///|
test "public review roundtrip and strict decisions" {
  let b = notebook("base","{}")
  let o = notebook("ours","{}")
  let t = notebook("theirs","{}")
  let r = @cells.merge(b,o,t)
  let restored = @cells.restore_review(@cells.canonical(r.to_json()))
  assert_eq(restored.conflicts(),["/cells/a"])
  assert_true(restored.to_text().contains("theirs"))
  assert_true((try { let _ = restored.apply_decisions(@cells.canonical(restored.decision_template())); false } catch { _ => true }))
  let output = restored.resolve({"/cells/a": @cells.Ours})
  assert_true(output.contains("ours"))
}
