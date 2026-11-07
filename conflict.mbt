///|
/// Caller-owned snapshots; absence is distinct from a present JSON null value.
pub(all) struct Conflict {
  path : String
  kind : String
  base : Json
  ours : Json
  theirs : Json
}

///|
fn at_path(value : Json, path : String) -> Json? raise MergeError {
  if path == "/cell-order" {
    return Some(Json::array(cells(value).map(c => Json::string(id(c)))))
  }
  if path.strip_prefix("/cells/") is Some(key) {
    return index(value).get(key.to_owned())
  }
  guard path.strip_prefix("/notebook/") is Some(key) else {
    raise Invalid("Unknown conflict path: " + path)
  }
  let key = key
    .to_owned()
    .replace_all(old="~1", new="/")
    .replace_all(old="~0", new="~")
  object(value).get(key)
}

///|
fn presence(value : Json?) -> Json {
  match value {
    None => Json::object({ "present": Json::boolean(false) })
    Some(v) => Json::object({ "present": Json::boolean(true), "value": v })
  }
}

///|
pub fn Review::details(self : Review) -> Array[Conflict] raise MergeError {
  // Parse fresh snapshots so callers cannot mutate the private merge inputs.
  fn fresh(raw : String) -> Json raise MergeError {
    @json.parse(
      raw,
      max_nesting_depth=64,
      reject_duplicate_keys=true,
      preserve_number_repr=true,
    ) catch {
      _ => raise Invalid("Corrupt internal notebook snapshot")
    }
  }
  let b = fresh(self.base.raw)
  let o = fresh(self.ours.raw)
  let t = fresh(self.theirs.raw)
  self.conflicts.map(path => {
    let bv = at_path(b, path)
    let ov = at_path(o, path)
    let tv = at_path(t, path)
    let kind = if path == "/cell-order" {
      "cell-order"
    } else if path.has_prefix("/notebook/") {
      "notebook-field"
    } else if ov is None || tv is None {
      "delete-edit"
    } else {
      "cell-content-or-output"
    }
    {
      path,
      kind,
      base: presence(bv),
      ours: presence(ov),
      theirs: presence(tv),
    }
  })
}

///|
pub fn Conflict::to_json(self : Conflict) -> Json {
  Json::object({
    "path": Json::string(self.path),
    "kind": Json::string(self.kind),
    "base": self.base,
    "ours": self.ours,
    "theirs": self.theirs,
  })
}

///|
pub fn Review::to_text(self : Review) -> String raise MergeError {
  let lines = [
    "MoonCellMerge: " + self.conflicts.length().to_string() + " conflict(s)",
  ]
  for c in self.details() {
    lines.push(Json::string(c.path).stringify() + " [" + c.kind + "]")
    lines.push("  base: " + canonical(c.base))
    lines.push("  ours: " + canonical(c.ours))
    lines.push("  theirs: " + canonical(c.theirs))
    lines.push(
      "  Select base/ours/theirs; /cell-order also needs a complete retained-ID array.",
    )
  }
  lines.join("\n")
}
