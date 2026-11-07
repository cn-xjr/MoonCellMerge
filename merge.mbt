///|
pub(all) suberror MergeError {
  Invalid(String)
}

///|
pub struct Notebook {
  priv raw : String
  priv value : Json
}

///|
pub struct Review {
  priv base : Notebook
  priv ours : Notebook
  priv theirs : Notebook
  priv conflicts : Array[String]
}

///|
pub(all) enum Choice {
  Base
  Ours
  Theirs
}

///|
fn object(value : Json) -> Map[String, Json] raise MergeError {
  guard value is Object(m) else { raise Invalid("Expected JSON object") }
  m
}

///|
fn cells(value : Json) -> Array[Json] raise MergeError {
  guard object(value).get("cells") is Some(Array(a)) else {
    raise Invalid("Expected cells array")
  }
  a
}

///|
fn id(cell : Json) -> String raise MergeError {
  guard object(cell).get("id") is Some(String(s)) else {
    raise Invalid("Every cell requires a stable id")
  }
  s
}

///|
fn source(cell : Json) -> String raise MergeError {
  match object(cell).get("source") {
    Some(String(s)) => s
    Some(Array(a)) => {
      let out = StringBuilder()
      for part in a {
        guard part is String(s) else {
          raise Invalid("source array must contain strings")
        }
        out.write_string(s)
      }
      out.to_string()
    }
    _ => raise Invalid("Expected cell source")
  }
}

///|
pub fn read_notebook(raw : String) -> Notebook raise MergeError {
  if raw.length() > 4_000_000 {
    raise Invalid("Input exceeds 4 million UTF-16 units")
  }
  let value = @json.parse(
    raw,
    max_nesting_depth=64,
    reject_duplicate_keys=true,
    preserve_number_repr=true,
  ) catch {
    e => raise Invalid("Invalid JSON: " + e.to_string())
  }
  let m = object(value)
  if m.get("nbformat") != Some(Json::number(4)) ||
    m.get("nbformat_minor") != Some(Json::number(5)) {
    raise Invalid("Only nbformat 4.5 is supported; explicit upgrade required")
  }
  let _ = object(m.get("metadata").unwrap_or(Json::null()))
  let seen : Map[String, Bool] = Map([])
  let a = cells(value)
  if a.length() > 10000 {
    raise Invalid("Cell count exceeds 10000")
  }
  for c in a {
    let key = id(c)
    if key.is_empty() ||
      key.length() > 64 ||
      !key
      .iter()
      .all(c => {
        (c >= 'a' && c <= 'z') ||
        (c >= 'A' && c <= 'Z') ||
        (c >= '0' && c <= '9') ||
        c == '-' ||
        c == '_'
      }) {
      raise Invalid("Invalid cell id: " + key)
    }
    if seen.contains(key) {
      raise Invalid("Duplicate cell id: " + key)
    }
    seen[key] = true
    let cm = object(c)
    let _ = source(c)
    let _ = object(cm.get("metadata").unwrap_or(Json::null()))
    match cm.get("cell_type") {
      Some(String("code")) => {
        guard cm.get("outputs") is Some(Array(_)) else {
          raise Invalid("Code cell requires outputs array: " + key)
        }
        match cm.get("execution_count") {
          Some(Null) => ()
          Some(Number(n, ..)) if n >= 0 && n <= 2147483647 && n.floor() == n =>
            ()
          _ => raise Invalid("Invalid execution_count: " + key)
        }
      }
      Some(String("markdown" | "raw")) => ()
      _ => raise Invalid("Unsupported cell_type: " + key)
    }
  }
  { raw, value, }
}

///|
// Comparing canonical number spellings rather than Double equality avoids
// treating distinct large integers as the same value. Objects sort their keys.
pub fn canonical(value : Json) -> String {
  match value {
    Object(m) => {
      let keys = m.keys().to_array()
      keys.sort()
      "{" +
      keys
      .map(k => Json::string(k).stringify() + ":" + canonical(m[k]))
      .join(",") +
      "}"
    }
    Array(a) => "[" + a.map(canonical).join(",") + "]"
    _ => value.stringify()
  }
}

///|
fn same(a : Json?, b : Json?) -> Bool {
  match (a, b) {
    (None, None) => true
    (Some(x), Some(y)) => canonical(x) == canonical(y)
    _ => false
  }
}

///|
fn pick(
  path : String,
  base : Json?,
  ours : Json?,
  theirs : Json?,
  choices : Map[String, Choice],
  conflicts : Array[String],
) -> Json? {
  if same(ours, theirs) {
    return ours
  }
  if same(base, ours) {
    return theirs
  }
  if same(base, theirs) {
    return ours
  }
  conflicts.push(path)
  match choices.get(path) {
    Some(Base) => base
    Some(Theirs) => theirs
    _ => ours
  }
}

///|
fn keys3(
  a : Map[String, Json],
  b : Map[String, Json],
  c : Map[String, Json],
) -> Array[String] {
  let keys : Map[String, Bool] = Map([])
  for m in [a, b, c] {
    for k in m.keys() {
      keys[k] = true
    }
  }
  let out = keys.keys().to_array()
  out.sort()
  out
}

///|
fn index(value : Json) -> Map[String, Json] raise MergeError {
  let out : Map[String, Json] = Map([])
  for c in cells(value) {
    out[id(c)] = c
  }
  out
}

///|
fn pointer(key : String) -> String {
  let out = StringBuilder()
  for c in key {
    match c {
      '~' => out.write_string("~0")
      '/' => out.write_string("~1")
      _ => out.write_char(c)
    }
  }
  "/notebook/" + out.to_string()
}

///|
fn merge_value(
  r : Review,
  choices : Map[String, Choice],
  order_override? : Array[String],
) -> (Json, Array[String]) raise MergeError {
  let conflicts : Array[String] = []
  let b = object(r.base.value)
  let o = object(r.ours.value)
  let t = object(r.theirs.value)
  let out : Map[String, Json] = Map([])
  for k in keys3(b, o, t) {
    if k == "cells" {
      continue
    }
    if pick(pointer(k), b.get(k), o.get(k), t.get(k), choices, conflicts)
      is Some(v) {
      out[k] = v
    }
  }
  let bi = index(r.base.value)
  let oi = index(r.ours.value)
  let ti = index(r.theirs.value)
  let merged : Map[String, Json] = Map([])
  for key in keys3(bi, oi, ti) {
    let path = "/cells/" + key
    let composed = compose_cell(bi.get(key), oi.get(key), ti.get(key))
    let mut chosen = if composed is Some(c) {
      Some(c)
    } else {
      pick(path, bi.get(key), oi.get(key), ti.get(key), choices, conflicts)
    }
    if conflicts.contains(path) &&
      (oi.get(key) is None) != (ti.get(key) is None) &&
      !conflicts.contains("/cell-order") {
      conflicts.push("/cell-order")
    }
    // A source-changing edit with retained output requires an explicit whole-cell
    // choice. We never silently erase execution evidence or certify its freshness.
    if chosen is Some(c) && bi.get(key) is Some(old) && source(c) != source(old) {
      if object(c).get("outputs") is Some(Array(outputs)) &&
        !outputs.is_empty() &&
        !conflicts.contains(path) {
        conflicts.push(path)
        chosen = match choices.get(path) {
          Some(Base) => bi.get(key)
          Some(Theirs) => ti.get(key)
          _ => oi.get(key)
        }
      }
    }
    if chosen is Some(c) {
      merged[key] = c
    }
  }
  fn order(value : Json) -> Json raise MergeError {
    Json::array(cells(value).map(c => Json::string(id(c))))
  }
  // Entire cell-id order is atomic in v0.1. One-sided insert/delete/move works;
  // simultaneous incompatible order edits require review, never arbitrary sort.
  let selected = pick(
    "/cell-order",
    Some(order(r.base.value)),
    Some(order(r.ours.value)),
    Some(order(r.theirs.value)),
    choices,
    conflicts,
  ).unwrap()
  guard selected is Array(original_ids) else {
    raise Invalid("Internal order error")
  }
  let ids = match order_override {
    Some(a) => a.map(Json::string)
    None => original_ids
  }
  let a : Array[Json] = []
  let seen : Map[String, Bool] = Map([])
  for v in ids {
    guard v is String(key) else { raise Invalid("Internal id error") }
    if merged.get(key) is Some(c) {
      if seen.contains(key) {
        raise Invalid("Duplicate cell in chosen order")
      }
      seen[key] = true
      a.push(c)
    } else if order_override is Some(_) {
      raise Invalid("Unknown cell in chosen order")
    }
  }
  // A chosen order may omit a cell retained by a delete/edit resolution. Refuse
  // instead of losing that cell. The reviewer must choose a compatible order.
  if a.length() != merged.length() {
    if order_override is Some(_) {
      raise Invalid("Chosen cell order omits retained cells")
    }
    if !conflicts.contains("/cell-order") {
      conflicts.push("/cell-order")
    }
    for k in keys3(merged, Map([]), Map([])) {
      if !seen.contains(k) {
        a.push(merged[k])
      }
    }
  }
  out["cells"] = Json::array(a)
  (Json::object(out), conflicts)
}

///|
pub fn merge(
  base : Notebook,
  ours : Notebook,
  theirs : Notebook,
) -> Review raise MergeError {
  if base.raw.length() + ours.raw.length() + theirs.raw.length() > 1_000_000 {
    raise Invalid("Combined merge inputs exceed 1 million UTF-16 units")
  }
  let r = { base, ours, theirs, conflicts: [], }
  let (_, conflicts) = merge_value(r, Map([]))
  { ..r, conflicts, }
}

///|
pub fn Review::conflicts(self : Review) -> Array[String] {
  self.conflicts.copy()
}

///|
pub fn Review::to_json(self : Review) -> Json {
  Json::object({
    "version": Json::number(1),
    "base": Json::string(self.base.raw),
    "ours": Json::string(self.ours.raw),
    "theirs": Json::string(self.theirs.raw),
    "conflicts": Json::array(self.conflicts.map(Json::string)),
  })
}

///|
pub fn restore_review(text : String) -> Review raise MergeError {
  if text.length() > 16_000_000 {
    raise Invalid("Review exceeds limit")
  }
  let v = @json.parse(
    text,
    max_nesting_depth=64,
    reject_duplicate_keys=true,
    preserve_number_repr=true,
  ) catch {
    _ => raise Invalid("Invalid review JSON")
  }
  let m = object(v)
  fn get(m : Map[String, Json], key : String) -> String raise MergeError {
    guard m.get(key) is Some(String(s)) else {
      raise Invalid("Missing review input " + key)
    }
    s
  }
  let r = merge(
    read_notebook(get(m, "base")),
    read_notebook(get(m, "ours")),
    read_notebook(get(m, "theirs")),
  )
  if canonical(r.to_json()) != canonical(v) {
    raise Invalid("Review fields/version/conflicts do not match replay")
  }
  r
}

///|
pub fn Review::resolve(
  self : Review,
  choices : Map[String, Choice],
  order? : Array[String],
) -> String raise MergeError {
  if choices.length() != self.conflicts.length() ||
    !self.conflicts.iter().all(k => choices.contains(k)) {
    raise Invalid(
      "Supply exactly one choice for every conflict; no unknown choices",
    )
  }
  if order is Some(_) && !self.conflicts.contains("/cell-order") {
    raise Invalid("Unexpected custom order")
  }
  let (value, actual) = merge_value(self, choices, order_override?=order)
  if actual.contains("/cell-order") && order is None {
    raise Invalid("Order conflict requires an explicit complete order array")
  }
  let text = canonical(value)
  let _ = read_notebook(text)
  text
}
