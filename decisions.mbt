///|
/// Empty choices deliberately remain incomplete when the review has conflicts.
/// No side is silently selected for the reviewer.
pub fn Review::decision_template(self : Review) -> Json {
  Json::object({ "review": self.to_json(), "choices": Json::empty_object() })
}

///|
/// Bind explicit decisions to the exact current three inputs before resolving.
pub fn Review::apply_decisions(
  self : Review,
  text : String,
) -> String raise MergeError {
  if text.length() > 16_000_000 {
    raise Invalid("Decision document exceeds 16 million UTF-16 units")
  }
  let doc = @json.parse(
    text,
    max_nesting_depth=64,
    reject_duplicate_keys=true,
    preserve_number_repr=true,
  ) catch {
    _ =>
      raise Invalid(
        "Invalid decision JSON: require unique keys and depth <= 64",
      )
  }
  let m = object(doc)
  if m.length() < 2 ||
    m.length() > 3 ||
    !m.contains("review") ||
    !m.contains("choices") {
    raise Invalid("Decision fields: review, choices, optional order")
  }
  if m.length() == 3 && !m.contains("order") {
    raise Invalid("Unknown decision field")
  }
  if canonical(m["review"]) != canonical(self.to_json()) {
    raise Invalid(
      "Decisions are stale: review inputs do not match current files",
    )
  }
  let _ = restore_review(canonical(m["review"]))
  let c = object(m["choices"])
  let choices : Map[String, Choice] = Map([])
  for (key, v) in c {
    choices[key] = match v {
      String("base") => Base
      String("ours") => Ours
      String("theirs") => Theirs
      _ => raise Invalid("Choice must be base, ours, or theirs")
    }
  }
  let order : Array[String]? = match m.get("order") {
    None => None
    Some(Array(ids)) =>
      Some(
        ids.map(v => {
          guard v is String(s) else {
            raise Invalid("Order must contain cell IDs")
          }
          s
        }),
      )
    _ => raise Invalid("order must be an array")
  }
  self.resolve(choices, order?)
}
