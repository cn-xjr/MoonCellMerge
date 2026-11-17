///|
test "malformed output envelopes report the exact field and do not poison later reads" {
  for
    pair in [
      ("null", ""),
      ("{}", "/output_type"),
      ("{\"output_type\":\"stream\",\"name\":\"other\"}", "/name"),
      ("{\"output_type\":\"stream\",\"name\":\"stdout\",\"text\":[1]}", "/text"),
      (
        "{\"output_type\":\"display_data\",\"data\":{},\"metadata\":1}", "/metadata",
      ),
      (
        "{\"output_type\":\"execute_result\",\"data\":{},\"metadata\":{},\"execution_count\":1.0}",
        "/execution_count",
      ),
      (
        "{\"output_type\":\"error\",\"ename\":\"E\",\"evalue\":\"x\",\"traceback\":\"x\"}",
        "/traceback",
      ),
    ] {
    let (malformed, field) = pair
    let error = try {
      let _ = nb(cell("output", "", outputs="[" + malformed + "]"))
      ""
    } catch {
      Invalid(msg) => msg
    }
    assert_true(error.has_suffix("/cells/output/outputs/0" + field))
  }
  let output = "[{\"output_type\":\"stream\",\"name\":\"stderr\",\"text\":[\"one\",\"two\"]},{\"output_type\":\"display_data\",\"data\":{\"application/json\":{\"x\":9007199254740993}},\"metadata\":{}},{\"output_type\":\"execute_result\",\"data\":{},\"metadata\":{},\"execution_count\":2147483647},{\"output_type\":\"error\",\"ename\":\"E\",\"evalue\":\"x\",\"traceback\":[]},{\"output_type\":\"vendor_extension\",\"payload\":[null,7]}]"
  let n = nb(cell("output", "", outputs=output))
  let merged = merge(n, n, n).resolve(Map([]))
  assert_eq(merged, canonical(n.value))
  assert_eq(canonical(read_notebook(merged).value), merged)
}
