///|
/// A custom source can require all inputs to have empty execution evidence,
/// or explicitly clear outputs and the execution count in the result.
pub(all) enum ExecutionPolicy {
  RequireEmpty
  ClearExecution
}

///|
pub(all) enum FieldDecision {
  Take(Choice)
  EditSource(String, ExecutionPolicy)
}

///|
priv struct FieldPlan {
  conflicts : Array[Conflict]
  whole_choices : Map[String, Choice]
  resolved_cells : Map[String, Json]
}

///|
fn edit_source(
  path : String,
  base : Json?,
  ours : Json?,
  theirs : Json?,
  text : String,
  execution : ExecutionPolicy,
) -> Json raise MergeError {
  guard base is Some(Object(bm)) &&
    ours is Some(Object(om)) &&
    theirs is Some(Object(tm)) else {
    raise Invalid("A source edit requires a cell in all three inputs: " + path)
  }
  guard bm.get("cell_type") is Some(String(kind)) &&
    same(bm.get("cell_type"), om.get("cell_type")) &&
    same(bm.get("cell_type"), tm.get("cell_type")) else {
    raise Invalid(
      "A source edit requires the same cell type in all inputs: " + path,
    )
  }
  for m in [bm, om, tm] {
    match m.get("attachments") {
      None => ()
      Some(Object(files)) if files.is_empty() => ()
      _ => raise Invalid("Choose a branch for a cell with attachments: " + path)
    }
    if !same(bm.get("attachments"), m.get("attachments")) {
      raise Invalid("Choose a branch when attachment fields differ: " + path)
    }
    if kind != "code" &&
      (m.contains("outputs") || m.contains("execution_count")) {
      raise Invalid("Choose a branch for non-code execution fields: " + path)
    }
    if execution is RequireEmpty && has_execution_evidence(m) {
      raise Invalid(
        "Custom source requires explicit execution clearing: " + path,
      )
    }
  }
  let updated = object(content_group(bm))
  updated["source"] = Json::string(text)
  if execution is ClearExecution {
    if kind != "code" {
      raise Invalid("Execution clearing only applies to code cells: " + path)
    }
    updated["execution_count"] = Json::null()
    updated["outputs"] = Json::array([])
  }
  Json::object(updated)
}

///|
fn snapshot_value(snapshot : Json) -> Json? {
  if snapshot is Object(fields) {
    fields.get("value")
  } else {
    None
  }
}

///|
fn Review::plan_fields(
  self : Review,
  decisions : Map[String, FieldDecision],
) -> FieldPlan raise MergeError {
  let conflicts : Array[Conflict] = []
  let whole_choices : Map[String, Choice] = Map([])
  let resolved_cells : Map[String, Json] = Map([])
  for c in self.details() {
    if c.path.strip_prefix("/cells/") is Some(cell_id) &&
      snapshot_value(c.base) is Some(Object(bm)) &&
      snapshot_value(c.ours) is Some(Object(om)) &&
      snapshot_value(c.theirs) is Some(Object(tm)) {
      let value = compose_existing_cell(bm, om, tm, review_execution=true, (
        field,
        b,
        o,
        t,
      ) => {
        let (suffix, kind) = match field {
          Content => ("/content", "cell-content")
          MetadataKey(key) =>
            ("/metadata/" + escape_pointer(key), "cell-metadata")
          Extension(key) => ("/fields/" + escape_pointer(key), "cell-field")
        }
        let path = c.path + suffix
        conflicts.push({
          path,
          kind,
          base: presence(b),
          ours: presence(o),
          theirs: presence(t),
        })
        match decisions.get(path) {
          Some(Take(side)) => select_side(b, o, t, Some(side))
          Some(EditSource(text, execution)) => {
            guard field is Content else {
              raise Invalid(
                "Custom source requires a cell content conflict: " +
                Json::string(path).stringify(),
              )
            }
            Some(edit_source(path, b, o, t, text, execution))
          }
          None => o
        }
      })
      resolved_cells[cell_id.to_owned()] = value
    } else {
      conflicts.push(c)
      match decisions.get(c.path) {
        Some(Take(side)) => whole_choices[c.path] = side
        Some(EditSource(_, _)) =>
          raise Invalid(
            "Custom source requires a cell content conflict: " +
            Json::string(c.path).stringify(),
          )
        None => ()
      }
    }
  }
  { conflicts, whole_choices, resolved_cells, }
}

///|
/// Return caller-owned snapshots for conflicting cell content groups, metadata
/// keys and extension fields. Cell existence and notebook conflicts retain
/// their existing paths. The path suffixes escape keys as JSON Pointers.
pub fn Review::field_details(self : Review) -> Array[Conflict] raise MergeError {
  self.plan_fields(Map([])).conflicts
}

///|
pub fn Review::field_conflict_report(self : Review) -> Json raise MergeError {
  Json::object({
    "version": Json::number(2),
    "requires_order": Json::boolean(self.conflicts.contains("/cell-order")),
    "conflicts": Json::array(self.field_details().map(c => c.to_json())),
  })
}

///|
/// Resolve field paths from field_details while preserving independent changes.
pub fn Review::resolve_fields(
  self : Review,
  choices : Map[String, FieldDecision],
  order? : Array[String],
) -> String raise MergeError {
  let plan = self.plan_fields(choices)
  verify_decisions(
    plan.conflicts.map(c => c.path),
    key => choices.contains(key),
    choices.length(),
    order,
  )
  self.resolve_value(
    plan.whole_choices,
    order,
    cell_overrides=plan.resolved_cells,
  )
}
