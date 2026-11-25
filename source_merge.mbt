///|
priv struct SourceEdit {
  earliest_start : Int32
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
  // Match the suffix independently. When it overlaps the common prefix,
  // an equally short insertion or deletion can slide across that overlap.
  let mut base_suffix = base.length()
  let mut changed_suffix = changed.length()
  while base_suffix > 0 &&
        changed_suffix > 0 &&
        base[base_suffix - 1] == changed[changed_suffix - 1] {
    base_suffix -= 1
    changed_suffix -= 1
  }
  let suffix_start = if base_suffix < changed_suffix {
    base_suffix
  } else {
    changed_suffix
  }
  let earliest_start = if suffix_start < start { suffix_start } else { start }
  let shift = start - earliest_start
  {
    earliest_start,
    start,
    end: base_suffix + shift,
    replacement: changed[start:changed_suffix + shift].to_owned(),
  }
}

///|
// The chosen edit is the rightmost placement. Its end must precede even
// the leftmost placement of the other edit; touching an insertion is unsafe.
fn source_edit_precedes(first : SourceEdit, second : SourceEdit) -> Bool {
  if first.start == first.end || second.start == second.end {
    first.end < second.earliest_start
  } else {
    first.end <= second.earliest_start
  }
}

///|
fn unique_lines(lines : Array[String]) -> Map[String, Int32] {
  let positions : Map[String, Int32] = Map([])
  for i, line in lines {
    positions[line] = if positions.contains(line) { -1 } else { i }
  }
  positions
}

///|
// Only lines unique in all three inputs can split a competing edit. Repeated
// lines cannot establish which occurrence either branch meant to keep.
fn compose_anchored_source(
  base : Array[String],
  ours : Array[String],
  theirs : Array[String],
) -> String? {
  let bp = unique_lines(base)
  let op = unique_lines(ours)
  let tp = unique_lines(theirs)
  let anchors : Array[(Int32, Int32, Int32)] = []
  let mut oi = -1
  let mut ti = -1
  for i, line in base {
    if bp[line] == i &&
      op.get(line) is Some(o) &&
      o >= 0 &&
      tp.get(line) is Some(t) &&
      t >= 0 {
      if o <= oi || t <= ti {
        return None
      }
      anchors.push((i, o, t))
      oi = o
      ti = t
    }
  }
  if anchors.is_empty() {
    return None
  }
  anchors.push((base.length(), ours.length(), theirs.length()))
  let result = StringBuilder()
  let mut last_b = 0
  let mut last_o = 0
  let mut last_t = 0
  for anchor in anchors {
    let (b, o, t) = anchor
    let before = base[last_b:b].to_owned()
    let left = ours[last_o:o].to_owned()
    let right = theirs[last_t:t].to_owned()
    let selected = if left == right || right == before {
      left
    } else if left == before {
      right
    } else {
      return None
    }
    for line in selected {
      result.write_string(line)
    }
    if b < base.length() {
      result.write_string(base[b])
    }
    last_b = b + 1
    last_o = o + 1
    last_t = t + 1
  }
  Some(result.to_string())
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
  let (first, second) = if source_edit_precedes(a, c) {
    (a, c)
  } else if source_edit_precedes(c, a) {
    (c, a)
  } else if a.earliest_start < a.start || c.earliest_start < c.start {
    return None
  } else {
    return compose_anchored_source(base, ours, theirs)
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
  for k in ["outputs", "execution_count", "attachments"] {
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
    let result = object(content_group(bm))
    result["source"] = Json::string(text)
    Some(Json::object(result))
  } else {
    None
  }
}
