///|
fn is_multiline(value : Json?) -> Bool {
  match value {
    Some(String(_)) => true
    Some(Array(parts)) => parts.iter().all(p => p is String(_))
    _ => false
  }
}

///|
// Check the envelope; MIME values and producer extensions remain untouched.
fn validate_output(value : Json, path : String) -> Unit raise MergeError {
  guard value is Object(fields) else {
    raise Invalid("Expected output object at " + path)
  }
  guard fields.get("output_type") is Some(String(kind)) && !kind.is_empty() else {
    raise Invalid("Expected nonempty output type at " + path + "/output_type")
  }
  match kind {
    "stream" => {
      guard fields.get("name") is Some(String("stdout" | "stderr")) else {
        raise Invalid("Expected stdout or stderr at " + path + "/name")
      }
      guard is_multiline(fields.get("text")) else {
        raise Invalid("Expected string or string array at " + path + "/text")
      }
    }
    "display_data" | "execute_result" => {
      for key in ["data", "metadata"] {
        guard fields.get(key) is Some(Object(_)) else {
          raise Invalid("Expected JSON object at " + path + "/" + key)
        }
      }
      if kind == "execute_result" {
        let _ = structural_integer(
          fields.get("execution_count"),
          path + "/execution_count",
        )
      }
    }
    "error" => {
      for key in ["ename", "evalue"] {
        guard fields.get(key) is Some(String(_)) else {
          raise Invalid("Expected string at " + path + "/" + key)
        }
      }
      guard fields.get("traceback") is Some(Array(_)) &&
        is_multiline(fields.get("traceback")) else {
        raise Invalid("Expected string array at " + path + "/traceback")
      }
    }
    _ => ()
  }
}
