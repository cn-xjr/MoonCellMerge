///|
test "compact bindings hash exact UTF-16LE text without a BOM" {
  assert_eq(
    notebook_digest("A🌙\r\n"),
    Json::string(
      "aa103b1125c860db454a204ff7ac8c368224cb7f5586e5fed85a7d873a9687e9",
    ),
  )
  let b = nb(cell("a", "base"))
  let o = nb(cell("a", "ours"))
  let t = nb(cell("a", "theirs"))
  let r = merge(b, o, t)
  let compact = canonical(r.compact_review())
  assert_eq(restore_compact_review(compact, b, o, t).conflicts(), r.conflicts())
  let whitespace = read_notebook(t.raw + "\n")
  for parts in [(b, t, o), (b, o, whitespace)] {
    let (base, ours, theirs) = parts
    assert_true(
      try {
        let _ = restore_compact_review(compact, base, ours, theirs)
        false
      } catch {
        Invalid(msg) => msg.contains("stale")
      },
    )
  }
  let tampered = object(r.compact_review())
  tampered["conflicts"] = Json::array([])
  assert_true(
    try {
      let _ = restore_compact_review(canonical(Json::object(tampered)), b, o, t)
      false
    } catch {
      Invalid(msg) => msg.contains("stale")
    },
  )
  assert_true(
    try {
      let _ = restore_review(compact)
      false
    } catch {
      Invalid(msg) => msg.contains("BASE OURS THEIRS")
    },
  )
}

///|
test "review format switches above the previous combined limit" {
  let n = nb("")
  let at_limit = read_notebook(
    n.raw + " ".repeat(1_000_000 - 3 * n.raw.length()),
  )
  let above = read_notebook(at_limit.raw + " ")
  let legacy = merge(n, n, at_limit)
  assert_eq(review_version(legacy.to_json()), 1)
  assert_eq(restore_review(canonical(legacy.to_json())).conflicts(), [])
  let large = merge(n, n, above)
  let doc = large.to_json()
  assert_eq(review_version(doc), 2)
  assert_true(canonical(doc).length() < 512)
  assert_eq(
    restore_compact_review(canonical(doc), n, n, above).resolve(Map([])),
    canonical(n.value),
  )
  assert_eq(
    large.apply_decisions(canonical(large.decision_template())),
    canonical(n.value),
  )
}

///|
test "the per-notebook input and merged output bounds report their own errors" {
  let n = nb("")
  let at_limit = n.raw + " ".repeat(NotebookLimit - n.raw.length())
  let input = read_notebook(at_limit)
  assert_eq(merge(input, input, input).resolve(Map([])), canonical(n.value))
  assert_true(
    try {
      let _ = read_notebook(at_limit + " ")
      false
    } catch {
      Invalid(msg) => msg.contains("Notebook input exceeds")
    },
  )
  let b = nb(cell("a", "base") + "," + cell("b", "base"))
  let text = "z".repeat(NotebookLimit / 2)
  let o = nb(cell("a", text) + "," + cell("b", "base"))
  let t = nb(cell("a", "base") + "," + cell("b", text))
  let r = merge(b, o, t)
  assert_eq(r.conflicts(), [])
  assert_true(
    try {
      let _ = r.resolve(Map([]))
      false
    } catch {
      Invalid(msg) => msg.contains("Merged notebook exceeds")
    },
  )
}
