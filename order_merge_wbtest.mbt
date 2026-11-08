///|
test "independent insertions in different retained-base gaps compose" {
  let a = cell("a", "a")
  let b = cell("b", "b")
  let x = cell("x", "x")
  let y = cell("y", "y")
  let base = nb(a + "," + b)
  let ours = nb(x + "," + a + "," + b)
  let theirs = nb(a + "," + y + "," + b)
  let r = merge(base, ours, theirs)
  assert_eq(r.conflicts(), [])
  let text = r.resolve(Map([]))
  assert_eq(cells(read_notebook(text).value).map(id), ["x", "a", "y", "b"])
  assert_eq(text, merge(base, theirs, ours).resolve(Map([])))
  assert_eq(restore_review(canonical(r.to_json())).resolve(Map([])), text)
}

///|
test "independent deletions compose while competing gaps remain explicit" {
  let a = cell("a", "a")
  let b = cell("b", "b")
  let c = cell("c", "c")
  let r = merge(nb(a + "," + b + "," + c), nb(a + "," + c), nb(a + "," + b))
  assert_eq(r.conflicts(), [])
  assert_eq(cells(read_notebook(r.resolve(Map([]))).value).map(id), ["a"])
  let ambiguous = merge(
    nb(a),
    nb(cell("x", "x") + "," + a),
    nb(cell("y", "y") + "," + a),
  )
  assert_eq(ambiguous.conflicts(), ["/cell-order"])
}

///|
test "delete-edit plus insertion exposes order conflict exactly once" {
  let b = nb(cell("a", "old") + "," + cell("b", "b"))
  let o = nb(cell("b", "b"))
  let t = nb(cell("a", "new") + "," + cell("b", "b") + "," + cell("x", "x"))
  let r = merge(b, o, t)
  assert_eq(r.conflicts(), ["/cells/a", "/cell-order"])
  let result = r.resolve({ "/cells/a": Theirs, "/cell-order": Theirs }, order=[
    "a", "b", "x",
  ])
  assert_eq(cells(read_notebook(result).value).map(id), ["a", "b", "x"])
}
