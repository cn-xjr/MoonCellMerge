///|
priv struct SourceEdit {
  start : Int32
  end : Int32
  replacement : Array[String]
}

///|
// Keep line terminators, including CRLF, and the absence of a trailing newline.
fn source_lines(text : String) -> Array[String] {
  let result : Array[String] = []
  let mut part = StringBuilder()
  for c in text {
    part.write_char(c)
    if c == '\n' {
      result.push(part.to_string())
      part = StringBuilder()
    }
  }
  let last = part.to_string()
  if !last.is_empty() {
    result.push(last)
  }
  result
}

///|
fn source_edit(base : Array[String], changed : Array[String]) -> SourceEdit {
  let mut start = 0
  while start < base.length() &&
        start < changed.length() &&
        base[start] == changed[start] {
    start += 1
  }
  let mut end = base.length()
  let mut tail = changed.length()
  while end > start && tail > start && base[end - 1] == changed[tail - 1] {
    end -= 1
    tail -= 1
  }
  { start, end, replacement: changed[start:tail].to_owned(), }
}

///|
fn compose_source(b : String, o : String, t : String) -> String? {
  if o == t {
    return Some(o)
  }
  if o == b {
    return Some(t)
  }
  if t == b {
    return Some(o)
  }
  if b.length() > 100_000 || o.length() > 100_000 || t.length() > 100_000 {
    return None
  }
  let base = source_lines(b)
  let ours = source_lines(o)
  let theirs = source_lines(t)
  if base.length() > 4000 || ours.length() > 4000 || theirs.length() > 4000 {
    return None
  }
  let a = source_edit(base, ours)
  let c = source_edit(base, theirs)
  let insertion = a.start == a.end || c.start == c.end
  let (first, second) = if (if insertion {
      a.end < c.start
    } else {
      a.end <= c.start
    }) {
    (a, c)
  } else if (if insertion { c.end < a.start } else { c.end <= a.start }) {
    (c, a)
  } else {
    return None
  }
  Some(
    base[0:first.start].to_owned().join("") +
    first.replacement.join("") +
    base[first.end:second.start].to_owned().join("") +
    second.replacement.join("") +
    base[second.end:].to_owned().join(""),
  )
}

///|
fn compose_source_group(
  bm : Map[String, Json],
  om : Map[String, Json],
  tm : Map[String, Json],
) -> Json? raise MergeError {
  for k in ["outputs", "execution_count"] {
    if !same(bm.get(k), om.get(k)) || !same(bm.get(k), tm.get(k)) {
      return None
    }
  }
  if !same(bm.get("cell_type"), om.get("cell_type")) ||
    !same(bm.get("cell_type"), tm.get("cell_type")) {
    return None
  }
  for m in [bm, om, tm] {
    match m.get("outputs") {
      None | Some(Array([])) => ()
      _ => return None
    }
    match m.get("execution_count") {
      None | Some(Null) => ()
      _ => return None
    }
  }
  if compose_source(
      source(Json::object(bm)),
      source(Json::object(om)),
      source(Json::object(tm)),
    )
    is Some(text) {
    let result = object(execution_group(bm))
    result["source"] = Json::string(text)
    Some(Json::object(result))
  } else {
    None
  }
}
