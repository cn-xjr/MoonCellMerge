///|
fn code_with_text(
  source_value : String,
  outputs : String,
) -> Notebook raise MergeError {
  nb(
    "{\"id\":\"a\",\"cell_type\":\"code\",\"metadata\":{},\"execution_count\":null,\"source\":" +
    source_value +
    ",\"outputs\":" +
    outputs +
    "}",
  )
}

///|
fn stream_with_text(text : String, name~ : String = "stdout") -> String {
  "[{\"output_type\":\"stream\",\"name\":\"" +
  name +
  "\",\"text\":" +
  text +
  "}]"
}

///|
test "source reserialization does not block an edit with cleared outputs" {
  let output = stream_with_text("\"1\\n\"")
  let base = code_with_text("[\"print(1)\\n\"]", output)
  let ours = code_with_text("\"print(1)\\n\"", output)
  let theirs = code_with_text("\"print(2)\\n\"", "[]")
  let r = merge(base, ours, theirs)
  assert_eq(r.conflicts(), [])
  assert_eq(r.resolve(Map([])), canonical(theirs.value))
  assert_eq(merge(base, theirs, ours).resolve(Map([])), canonical(theirs.value))
  let retained = code_with_text("\"print(2)\\n\"", output)
  assert_eq(merge(base, ours, retained).conflicts(), ["/cells/a"])
}

///|
test "stream text reserialization preserves real output edits and stream identity" {
  let code = "\"print(1)\""
  let base = code_with_text(code, stream_with_text("[\"ok\",\"\\n\"]"))
  let ours = code_with_text(code, stream_with_text("\"ok\\n\""))
  let theirs = code_with_text(code, stream_with_text("[\"failed\\n\"]"))
  let r = merge(base, ours, theirs)
  assert_eq(r.conflicts(), [])
  assert_eq(r.resolve(Map([])), canonical(theirs.value))
  let stderr = code_with_text(
    code,
    stream_with_text("\"ok\\n\"", name="stderr"),
  )
  assert_eq(merge(base, stderr, theirs).conflicts(), ["/cells/a"])
}

///|
test "equivalent new content chooses deterministic input representation" {
  let base = code_with_text("\"old\"", stream_with_text("\"old\""))
  let ours = code_with_text(
    "[\"a\",\"b\"]",
    stream_with_text("[\"new\",\"\\r\\n\"]"),
  )
  let theirs = code_with_text("\"ab\"", stream_with_text("\"new\\r\\n\""))
  // Source moved while both sides retained output. Equivalence cannot skip review.
  assert_eq(merge(base, ours, theirs).conflicts(), ["/cells/a"])
  let base = code_with_text("\"ab\"", stream_with_text("\"old\""))
  let first = merge(base, ours, theirs).resolve(Map([]))
  assert_eq(first, merge(base, theirs, ours).resolve(Map([])))
  assert_true(
    first == canonical(ours.value) || first == canonical(theirs.value),
  )
  let different_line_end = code_with_text(
    "\"ab\"",
    stream_with_text("\"new\\n\""),
  )
  assert_eq(merge(base, ours, different_line_end).conflicts(), ["/cells/a"])
}

///|
test "cell existence merging recognizes format-only branches but digest replay checks raw bytes" {
  let base = code_with_text("[]", stream_with_text("[]"))
  let reencoded = code_with_text("\"\"", stream_with_text("\"\""))
  let missing = nb("")
  assert_eq(
    merge(base, reencoded, missing).resolve(Map([])),
    canonical(missing.value),
  )
  let inserted = merge(missing, base, reencoded).resolve(Map([]))
  assert_eq(inserted, merge(missing, reencoded, base).resolve(Map([])))
  assert_eq(
    merge(base, base, reencoded).resolve(Map([])),
    canonical(base.value),
  )
  let binding = canonical(merge(base, base, base).compact_review())
  assert_true(
    try {
      let _ = restore_compact_review(binding, base, reencoded, base)
      false
    } catch {
      Invalid(message) => message.contains("stale")
    },
  )
}

///|
test "opaque producer output and JSON MIME arrays retain exact semantics" {
  let source = "\"x\""
  let base = code_with_text(
    source, "[{\"output_type\":\"vendor\",\"text\":[\"ab\"]}]",
  )
  let ours = code_with_text(
    source, "[{\"output_type\":\"vendor\",\"text\":\"ab\"}]",
  )
  let theirs = code_with_text(
    source, "[{\"output_type\":\"vendor\",\"text\":\"cd\"}]",
  )
  assert_eq(merge(base, ours, theirs).conflicts(), ["/cells/a"])
  fn mime(payload : String) -> Notebook raise MergeError {
    code_with_text(
      "\"x\"",
      "[{\"output_type\":\"display_data\",\"data\":{\"application/json\":" +
      payload +
      "},\"metadata\":{}}]",
    )
  }
  assert_eq(
    merge(mime("[\"ab\"]"), mime("\"ab\""), mime("[\"cd\"]")).conflicts(),
    ["/cells/a"],
  )
}
