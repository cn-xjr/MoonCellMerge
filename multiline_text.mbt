///|
fn join_multiline(value : Json?) -> String? {
  match value {
    Some(String(text)) => Some(text)
    Some(Array(parts)) => {
      let out = StringBuilder()
      for part in parts {
        guard part is String(text) else { return None }
        out.write_string(text)
      }
      Some(out.to_string())
    }
    _ => None
  }
}

///|
fn same_multiline(a : Json?, b : Json?) -> Bool {
  if same(a, b) {
    return true
  }
  match (join_multiline(a), join_multiline(b)) {
    (Some(left), Some(right)) => left == right
    _ => false
  }
}

///|
fn same_output(a : Json, b : Json) -> Bool {
  guard a is Object(left) &&
    b is Object(right) &&
    left.get("output_type") is Some(String("stream")) &&
    right.get("output_type") is Some(String("stream")) else {
    return same_json(a, b)
  }
  if left.length() != right.length() {
    return false
  }
  for key, value in left {
    let matches = if key == "text" {
      same_multiline(Some(value), right.get(key))
    } else {
      same(Some(value), right.get(key))
    }
    if !matches {
      return false
    }
  }
  true
}

///|
fn same_code_outputs(a : Json?, b : Json?) -> Bool {
  guard a is Some(Array(left)) && b is Some(Array(right)) else {
    return same(a, b)
  }
  if left.length() != right.length() {
    return false
  }
  for i in 0..<left.length() {
    if !same_output(left[i], right[i]) {
      return false
    }
  }
  true
}

///|
// Only Jupyter's standard multiline slots get semantic comparison. Values
// under extension keys or MIME bundles keep their exact JSON semantics.
fn same_cell_value(a : Json?, b : Json?) -> Bool {
  guard a is Some(Object(left)) && b is Some(Object(right)) else {
    return same(a, b)
  }
  let kind = left.get("cell_type")
  if left.length() != right.length() ||
    !same(kind, right.get("cell_type")) ||
    !same_multiline(left.get("source"), right.get("source")) {
    return false
  }
  for key, value in left {
    let matches = match key {
      "cell_type" | "source" => true
      "outputs" if kind is Some(String("code")) =>
        same_code_outputs(Some(value), right.get(key))
      _ => same(Some(value), right.get(key))
    }
    if !matches {
      return false
    }
  }
  true
}

///|
fn agreed_cell(base : Json?, ours : Json?, theirs : Json?) -> Json?? {
  if same(ours, theirs) {
    return Some(ours)
  }
  if same_cell_value(base, ours) {
    // With only representation differences on both sides, retain the base.
    return if same_cell_value(base, theirs) { Some(base) } else { Some(theirs) }
  }
  if same_cell_value(base, theirs) {
    return Some(ours)
  }
  if ours is Some(left) &&
    theirs is Some(right) &&
    same_cell_value(ours, theirs) {
    // Both branches made the same logical edit with different serialization.
    // Retain one input's representation deterministically in either side order.
    return if canonical(left) <= canonical(right) {
      Some(ours)
    } else {
      Some(theirs)
    }
  }
  None
}
