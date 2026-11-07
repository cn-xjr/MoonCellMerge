///|
// Source, cell type and execution evidence form one atomic group. Metadata
// changes may compose with this group; source from one branch must never be
// accidentally paired with another branch's output by field-wise merging.
fn execution_group(m : Map[String, Json]) -> Json {
  let out : Map[String, Json] = Map([])
  for k in ["cell_type", "source", "outputs", "execution_count"] {
    if m.get(k) is Some(v) {
      out[k] = v
    }
  }
  Json::object(out)
}

///|
fn compose_cell(b : Json?, o : Json?, t : Json?) -> Json? raise MergeError {
  guard b is Some(Object(bm)) && o is Some(Object(om)) && t is Some(Object(tm)) else {
    return None
  }
  let conflicts : Array[String] = []
  let choices : Map[String, Choice] = Map([])
  let group = pick(
    "execution",
    Some(execution_group(bm)),
    Some(execution_group(om)),
    Some(execution_group(tm)),
    choices,
    conflicts,
  ).unwrap()
  let out = object(group)
  for key in keys3(bm, om, tm) {
    if ["cell_type", "source", "outputs", "execution_count"].contains(key) {
      continue
    }
    if key == "metadata" &&
      bm.get(key) is Some(Object(bmeta)) &&
      om.get(key) is Some(Object(ometa)) &&
      tm.get(key) is Some(Object(tmeta)) {
      let metadata : Map[String, Json] = Map([])
      for name in keys3(bmeta, ometa, tmeta) {
        if pick(
            "metadata",
            bmeta.get(name),
            ometa.get(name),
            tmeta.get(name),
            choices,
            conflicts,
          )
          is Some(v) {
          metadata[name] = v
        }
      }
      out[key] = Json::object(metadata)
    } else if pick(
        key,
        bm.get(key),
        om.get(key),
        tm.get(key),
        choices,
        conflicts,
      )
      is Some(v) {
      out[key] = v
    }
  }
  if conflicts.is_empty() {
    Some(Json::object(out))
  } else {
    None
  }
}
