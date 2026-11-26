///|
/// Add choices for value conflicts and a complete `order` for an order
/// conflict. The template never selects a side or order for the reviewer.
pub fn Review::decision_template(self : Review) -> Json {
  Json::object({ "review": self.to_json(), "choices": Json::empty_object() })
}

///|
/// Build an input-bound version 2 template for field-level decisions.
pub fn Review::field_decision_template(self : Review) -> Json {
  Json::object({
    "version": Json::number(2),
    "review": self.to_json(),
    "choices": Json::empty_object(),
  })
}

///|
fn parse_side(value : Json) -> Choice raise MergeError {
  match value {
    String("base") => Base
    String("ours") => Ours
    String("theirs") => Theirs
    _ => raise Invalid("Choice must be base, ours, or theirs")
  }
}

///|
fn parse_field_decision(value : Json) -> FieldDecision raise MergeError {
  if value is Object(fields) {
    guard fields.length() == 2 &&
      fields.get("source") is Some(String(text)) &&
      fields.get("execution") is Some(String(execution)) else {
      raise Invalid("Custom source requires exactly source and execution")
    }
    let policy = match execution {
      "clear" => ClearExecution
      "require-empty" => RequireEmpty
      _ => raise Invalid("Execution policy must be clear or require-empty")
    }
    EditSource(text, policy)
  } else {
    Take(parse_side(value))
  }
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
  if !m.contains("review") || !m.contains("choices") {
    raise Invalid("Decision fields: review, choices, optional order")
  }
  for key in m.keys() {
    if !["review", "choices", "order", "version"].contains(key) {
      raise Invalid("Unknown decision field")
    }
  }
  let field_level = m.contains("version")
  if field_level &&
    structural_integer(m.get("version"), "decision version") != 2 {
    raise Invalid("Unsupported decision version")
  }
  if canonical(m["review"]) != canonical(self.to_json()) {
    raise Invalid(
      "Decisions are stale: review inputs do not match current files",
    )
  }
  let _ = restore_review(canonical(m["review"]))
  let c = object(m["choices"])
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
  if field_level {
    let choices : Map[String, FieldDecision] = Map([])
    for key, value in c {
      choices[key] = parse_field_decision(value)
    }
    self.resolve_fields(choices, order?)
  } else {
    let choices : Map[String, Choice] = Map([])
    for key, value in c {
      choices[key] = parse_side(value)
    }
    self.resolve(choices, order?)
  }
}
