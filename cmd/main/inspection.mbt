///|
// Keep the result on one terminal line, including terminal and bidi controls
// that the JSON serializer can legally leave unescaped.
fn inspection_quote(text : String) -> String {
  let quoted = StringBuilder()
  for ch in Json::string(text).stringify().iter() {
    let code = ch.to_int()
    if (code >= 0x7f && code <= 0x9f) ||
      code == 0x061c ||
      code is (0x200e | 0x200f) ||
      (code >= 0x2028 && code <= 0x202e) ||
      (code >= 0x2066 && code <= 0x2069) {
      let hex = code.to_string(radix=16)
      quoted.write_string("\\u" + "0".repeat(4 - hex.length()) + hex)
    } else {
      quoted.write_char(ch)
    }
  }
  quoted.to_string()
}

///|
fn inspection_excerpt(parts : Array[Json]) -> String {
  let prefix = StringBuilder()
  let mut count = 0
  for part in parts {
    guard part is String(text) else { return "(invalid text)" }
    for ch in text.iter() {
      if count == 96 {
        return inspection_quote(prefix.to_string()) + " …"
      }
      prefix.write_char(ch)
      count += 1
    }
  }
  inspection_quote(prefix.to_string())
}

///|
fn inspection_cell(cell : Map[String, Json]) -> String {
  let kind = match cell.get("cell_type") {
    Some(String(value)) => inspection_excerpt([Json::string(value)])
    _ => "(unknown)"
  }
  let source = match cell.get("source") {
    Some(String(_) as value) => inspection_excerpt([value])
    Some(Array(parts)) => inspection_excerpt(parts)
    _ => "(absent)"
  }
  let attachment_count = match cell.get("attachments") {
    Some(Object(files)) => files.length()
    _ => 0
  }
  let header = "\{kind} source=\{source}; attachments=\{attachment_count}"
  guard cell.get("cell_type") is Some(String("code")) else { return header }
  let count = inspection_scalar(
    cell.get("execution_count").unwrap_or(Json::null()),
  )
  let outputs = match cell.get("outputs") {
    Some(Array(items)) => {
      let kinds : Array[String] = []
      for i in 0..<items.length().min(6) {
        let label = match items[i] {
          { "output_type": String("stream"), "name": String(name), .. } =>
            "stream/" + name
          { "output_type": String(output_type), .. } => output_type
          _ => "unknown"
        }
        kinds.push(inspection_excerpt([Json::string(label)]))
      }
      if items.length() > kinds.length() {
        kinds.push("…")
      }
      "\{items.length()} [" + kinds.join(", ") + "]"
    }
    _ => "(absent)"
  }
  "\{header}; execution_count=\{count}; outputs=\{outputs}"
}

///|
fn inspection_scalar(value : Json) -> String {
  let chars = value.stringify().iter()
  let prefix = StringBuilder()
  for _ in 0..<96 {
    guard chars.next() is Some(ch) else { return prefix.to_string() }
    prefix.write_char(ch)
  }
  prefix.to_string() + (if chars.next() is Some(_) { " …" } else { "" })
}

///|
fn inspection_value(kind : String, snapshot : Json) -> String {
  match snapshot {
    { "value": Object(cell), .. } if kind
      is ("cell-content" | "delete-edit" | "cell-content-or-output") =>
      inspection_cell(cell)
    { "value": Array(ids), .. } if kind == "cell-order" => {
      let prefix : Array[String] = []
      for i in 0..<ids.length().min(6) {
        prefix.push(ids[i].stringify())
      }
      if ids.length() > prefix.length() {
        prefix.push("…")
      }
      "\{ids.length()} cell IDs [" + prefix.join(", ") + "]"
    }
    { "value": Array(items), .. } => "array (\{items.length()} items)"
    { "value": Object(fields), .. } => "object (\{fields.length()} keys)"
    { "value": String(_) as value, .. } => inspection_excerpt([value])
    { "value": value, .. } => inspection_scalar(value)
    _ => "(absent)"
  }
}

///|
fn inspection_summary(review : @merge.Review) -> String raise @merge.MergeError {
  let conflicts = review.field_details()
  let lines = ["MoonCellMerge: \{conflicts.length()} review item(s)"]
  for conflict in conflicts {
    lines.push(inspection_quote(conflict.path) + " [" + conflict.kind + "]")
    lines.push("  base: " + inspection_value(conflict.kind, conflict.base))
    lines.push("  ours: " + inspection_value(conflict.kind, conflict.ours))
    lines.push("  theirs: " + inspection_value(conflict.kind, conflict.theirs))
  }
  if !conflicts.is_empty() {
    if review.conflicts().contains("/cell-order") {
      lines.push("Set order to every retained cell ID exactly once.")
    }
    lines.push(
      "Use inspect-fields for full evidence and template-fields for decisions.",
    )
  }
  lines.join("\n")
}
