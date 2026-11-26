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

///|
fn ordered_notebook(ids : Array[String]) -> Notebook raise MergeError {
  nb(ids.map(key => cell(key, key)).join(","))
}

///|
test "independent moves at opposite ends compose without losing retained cells" {
  let b = ordered_notebook(["a", "b", "c", "d", "e", "f"])
  let o = ordered_notebook(["b", "a", "c", "d", "e", "f"])
  let t = ordered_notebook(["a", "b", "c", "d", "f", "e"])
  let r = merge(b, o, t)
  assert_eq(r.conflicts(), [])
  let text = r.resolve(Map([]))
  assert_eq(
    text,
    canonical(ordered_notebook(["b", "a", "c", "d", "f", "e"]).value),
  )
  assert_eq(merge(b, t, o).resolve(Map([])), text)
  assert_eq(restore_review(canonical(r.to_json())).resolve(Map([])), text)
}

///|
test "cyclic pairwise moves remain an order conflict with explicit recovery" {
  let b = ordered_notebook(["a", "b", "c"])
  let o = ordered_notebook(["b", "a", "c"])
  let t = ordered_notebook(["a", "c", "b"])
  let r = merge(b, o, t)
  assert_eq(r.conflicts(), ["/cell-order"])
  assert_eq(merge(b, t, o).conflicts(), r.conflicts())
  assert_eq(
    r.resolve(Map([]), order=["c", "b", "a"]),
    canonical(ordered_notebook(["c", "b", "a"]).value),
  )
}

///|
test "an insertion composes with moves only while its gap remains intact" {
  let b = ordered_notebook(["a", "b", "c", "d", "e", "f"])
  let o = ordered_notebook(["b", "a", "c", "x", "d", "e", "f"])
  let t = ordered_notebook(["a", "b", "c", "d", "f", "e"])
  let r = merge(b, o, t)
  assert_eq(r.conflicts(), [])
  let expected = canonical(
    ordered_notebook(["b", "a", "c", "x", "d", "f", "e"]).value,
  )
  assert_eq(r.resolve(Map([])), expected)
  assert_eq(merge(b, t, o).resolve(Map([])), expected)
  let displaced = ordered_notebook(["a", "y", "b", "c", "d", "f", "e"])
  assert_eq(merge(b, o, displaced).conflicts(), ["/cell-order"])
}

///|
test "the move limit applies to a shared window rather than notebook length" {
  for n in [MoveWindowLimit, MoveWindowLimit + 1] {
    let base = Array::makei(n, i => "id-" + i.to_string())
    let ours = base[1:].to_owned()
    ours.push(base[0])
    let theirs = base.copy()
    theirs[1] = base[2]
    theirs[2] = base[1]
    let expected = ours.copy()
    expected[0] = base[2]
    expected[1] = base[1]
    assert_eq(
      compose_moves(base, ours, theirs),
      if n == MoveWindowLimit {
        Some(expected)
      } else {
        None
      },
    )
  }
  let n = 2 * MoveWindowLimit
  let base = Array::makei(n, i => "id-" + i.to_string())
  let ours = base.copy()
  ours[0] = base[1]
  ours[1] = base[0]
  let theirs = base.copy()
  theirs[n - 2] = base[n - 1]
  theirs[n - 1] = base[n - 2]
  let expected = ours.copy()
  expected[n - 2] = base[n - 1]
  expected[n - 1] = base[n - 2]
  assert_eq(compose_moves(base, ours, theirs), Some(expected))
}

///|
test "all four-cell branch orders match an exhaustive constraint check" {
  let base = ["a", "b", "c", "d"]
  let permutations : Array[Array[String]] = []
  for a in base {
    for b in base {
      if b == a {
        continue
      }
      for c in base {
        if c == a || c == b {
          continue
        }
        for d in base {
          if d != a && d != b && d != c {
            permutations.push([a, b, c, d])
          }
        }
      }
    }
  }
  fn precedes(ids : Array[String], a : String, b : String) -> Bool {
    for key in ids {
      if key == a {
        return true
      }
      if key == b {
        return false
      }
    }
    false
  }
  for ours in permutations {
    for theirs in permutations {
      let possible = permutations.filter(candidate => {
        for i in 0..<base.length() {
          for j in (i + 1)..<base.length() {
            let a = base[i]
            let b = base[j]
            let keep = precedes(ours, a, b) && precedes(theirs, a, b)
            if precedes(candidate, a, b) != keep {
              return false
            }
          }
        }
        true
      })
      assert_true(possible.length() <= 1)
      assert_eq(compose_moves(base, ours, theirs), possible.get(0))
    }
  }
}
