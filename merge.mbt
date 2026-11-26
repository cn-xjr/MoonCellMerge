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
const NotebookLimit = 4_000_000

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
  if raw.length() > NotebookLimit {
    raise Invalid("Notebook input exceeds 4 million UTF-16 units")
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
  if structural_integer(m.get("nbformat"), "nbformat") != 4 ||
    structural_integer(m.get("nbformat_minor"), "nbformat_minor") != 5 {
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
    validate_attachments(
      cm.get("attachments"),
      "/cells/" + key + "/attachments",
    )
    match cm.get("cell_type") {
      Some(String("code")) => {
        guard cm.get("outputs") is Some(Array(outputs)) else {
          raise Invalid("Code cell requires outputs array: " + key)
        }
        for i, output in outputs {
          validate_output(output, "/cells/" + key + "/outputs/" + i.to_string())
        }
        match cm.get("execution_count") {
          Some(Null) => ()
          Some(Number(_, ..)) => {
            let _ = structural_integer(
              cm.get("execution_count"),
              "execution_count for " + key,
            )
          }
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
    (Some(x), Some(y)) => same_json(x, y)
    _ => false
  }
}

///|
// Traverse without serializing whole cells, especially large MIME payloads.
fn same_json(left : Json, right : Json) -> Bool {
  match (left, right) {
    (Object(a), Object(b)) =>
      a.length() == b.length() &&
      a
      .iter()
      .all(pair => {
        let (key, value) = pair
        same(Some(value), b.get(key))
      })
    (Array(a), Array(b)) => {
      if a.length() != b.length() {
        return false
      }
      for i in 0..<a.length() {
        if !same_json(a[i], b[i]) {
          return false
        }
      }
      true
    }
    (String(a), String(b)) => a == b
    (Number(_, ..), Number(_, ..)) => left.stringify() == right.stringify()
    (True, True) | (False, False) | (Null, Null) => true
    _ => false
  }
}

///|
// Some(None) means the agreed result is absence.
fn agreed(base : Json?, ours : Json?, theirs : Json?) -> Json?? {
  if same(ours, theirs) || same(base, theirs) {
    Some(ours)
  } else if same(base, ours) {
    Some(theirs)
  } else {
    None
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
  if agreed(base, ours, theirs) is Some(value) {
    return value
  }
  if !conflicts.contains(path) {
    conflicts.push(path)
  }
  select_side(base, ours, theirs, choices.get(path))
}

///|
fn select_side(
  base : Json?,
  ours : Json?,
  theirs : Json?,
  choice : Choice?,
) -> Json? {
  match choice {
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
fn escape_pointer(key : String) -> String {
  let out = StringBuilder()
  for c in key {
    match c {
      '~' => out.write_string("~0")
      '/' => out.write_string("~1")
      _ => out.write_char(c)
    }
  }
  out.to_string()
}

///|
fn pointer(key : String) -> String {
  "/notebook/" + escape_pointer(key)
}

///|
fn has_execution_evidence(m : Map[String, Json]) -> Bool {
  (m.get("outputs") is Some(Array(outputs)) && !outputs.is_empty()) ||
  m.get("execution_count") is Some(Number(_, ..))
}

///|
fn merge_value(
  r : Review,
  choices : Map[String, Choice],
  order_override? : Array[String],
  cell_overrides? : Map[String, Json],
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
    if k == "metadata" {
      if compose_notebook_metadata(b.get(k), o.get(k), t.get(k)) is Some(v) {
        out[k] = v
        continue
      }
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
    if cell_overrides is Some(overrides) && overrides.get(key) is Some(value) {
      merged[key] = value
      continue
    }
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
    // A source-changing edit with retained execution evidence requires a whole-cell
    // choice. We never silently erase execution evidence or certify its freshness.
    if chosen is Some(c) && bi.get(key) is Some(old) && source(c) != source(old) {
      if has_execution_evidence(object(c)) && !conflicts.contains(path) {
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
  // Compose compatible moves and insertion gaps, then fall back to explicit
  // review when the branches do not determine a safe order.
  let inferred_order = compose_order(
    r.base.value,
    r.ours.value,
    r.theirs.value,
    merged,
  )
  let selected = if inferred_order is Some(ids) {
    Json::array(ids.map(Json::string))
  } else {
    pick(
      "/cell-order",
      Some(order(r.base.value)),
      Some(order(r.ours.value)),
      Some(order(r.theirs.value)),
      choices,
      conflicts,
    ).unwrap()
  }
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
  let r = { base, ours, theirs, conflicts: [], }
  let (_, conflicts) = merge_value(r, Map([]))
  { ..r, conflicts, }
}

///|
pub fn Review::conflicts(self : Review) -> Array[String] {
  self.conflicts.copy()
}

///|
pub fn Review::resolve(
  self : Review,
  choices : Map[String, Choice],
  order? : Array[String],
) -> String raise MergeError {
  verify_decisions(
    self.conflicts,
    key => choices.contains(key),
    choices.length(),
    order,
  )
  self.resolve_value(choices, order)
}

///|
fn verify_decisions(
  paths : Array[String],
  has_choice : (String) -> Bool,
  choice_count : Int32,
  order : Array[String]?,
) -> Unit raise MergeError {
  let has_order_conflict = paths.contains("/cell-order")
  if order is Some(_) && !has_order_conflict {
    raise Invalid("Unexpected custom order")
  }
  let mut known = 0
  for path in paths {
    if has_choice(path) {
      known += 1
    } else if path != "/cell-order" {
      raise Invalid("Missing choice for " + Json::string(path).stringify())
    } else if order is None {
      raise Invalid("Order conflict requires an explicit complete order array")
    }
  }
  if choice_count != known {
    raise Invalid("Choices contain paths that are not in the review")
  }
}

///|
fn Review::resolve_value(
  self : Review,
  choices : Map[String, Choice],
  order : Array[String]?,
  cell_overrides? : Map[String, Json],
) -> String raise MergeError {
  let (value, actual) = merge_value(
    self,
    choices,
    order_override?=order,
    cell_overrides?,
  )
  if actual.contains("/cell-order") && order is None {
    raise Invalid("Order conflict requires an explicit complete order array")
  }
  let text = canonical(value)
  if text.length() > NotebookLimit {
    raise Invalid(
      "Merged notebook exceeds 4 million UTF-16 units; reduce input payloads explicitly and retry",
    )
  }
  let _ = read_notebook(text)
  text
}
