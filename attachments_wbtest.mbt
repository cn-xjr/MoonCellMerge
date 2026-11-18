///|
test "attachment containers fail with escaped paths and preserve opaque MIME data" {
  fn n(value : String) -> Notebook raise MergeError {
    nb(
      "{\"id\":\"m\",\"cell_type\":\"markdown\",\"source\":\"\",\"metadata\":{},\"attachments\":" +
      value +
      "}",
    )
  }
  for
    pair in [
      ("null", "/cells/m/attachments"),
      ("[]", "/cells/m/attachments"),
      ("{\"a/b~c\":null}", "/cells/m/attachments/a~1b~0c"),
      ("{\"a\":\"base64\"}", "/cells/m/attachments/a"),
    ] {
    let (value, path) = pair
    let diagnostic = try {
      let _ = n(value)
      ""
    } catch {
      Invalid(msg) => msg
    }
    assert_true(diagnostic.has_suffix(path))
  }
  let valid = n(
    "{\"figure.png\":{\"image/png\":[\"AA==\"],\"application/vendor+json\":{\"n\":9007199254740993}},\"empty\":{}}",
  )
  let text = merge(valid, valid, valid).resolve(Map([]))
  assert_eq(text, canonical(valid.value))
  assert_eq(canonical(read_notebook(text).value), text)
}
