///|
test "inspection distinguishes absent, null and opaque payloads" {
  assert_eq(inspection_value("cell-field", { "present": false }), "(absent)")
  assert_eq(
    inspection_value("cell-field", { "present": true, "value": null }),
    "null",
  )
  assert_eq(
    inspection_value("cell-field", { "value": { "ignored": "opaque" } }),
    "object (1 keys)",
  )
  assert_eq(
    inspection_excerpt([Json::string("🌙".repeat(96))]),
    "\"" + "🌙".repeat(96) + "\"",
  )
}

///|
test "inspection previews multiline code and caps output kinds" {
  let code : Json = {
    "source": ["a\n", "b"],
    "cell_type": "code",
    "execution_count": 2,
    "outputs": [
      { "output_type": "stream", "name": "stderr", "text": "payload" },
      { "output_type": "display_data", "data": { "image/png": "payload" } },
      { "output_type": "error" },
      { "output_type": "execute_result" },
      { "output_type": "stream", "name": "stdout" },
      { "output_type": "extension" },
      { "output_type": "hidden" },
    ],
  }
  assert_eq(
    inspection_value("cell-content", { "value": code }),
    (
      #|"code" source="a\nb"; attachments=0; execution_count=2; outputs=7 ["stream/stderr", "display_data", "error", "execute_result", "stream/stdout", "extension", …]
    ),
  )
}
