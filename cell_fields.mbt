///|
priv enum CellField {
  Content
  MetadataKey(String)
  Extension(String)
}

///|
let content_keys : Array[String] = [
  "cell_type", "source", "outputs", "execution_count", "attachments",
]

///|
// Keep source, type, attachments and execution evidence together.
fn content_group(m : Map[String, Json]) -> Json {
  let out : Map[String, Json] = Map([])
  for k in content_keys {
    if m.get(k) is Some(v) {
      out[k] = v
    }
  }
  Json::object(out)
}

///|
fn compose_existing_cell(
  bm : Map[String, Json],
  om : Map[String, Json],
  tm : Map[String, Json],
  review_execution~ : Bool,
  conflict : (CellField, Json?, Json?, Json?) -> Json? raise MergeError,
) -> Json raise MergeError {
  let bg = content_group(bm)
  let og = content_group(om)
  let tg = content_group(tm)
  let content = match agreed(Some(bg), Some(og), Some(tg)) {
    Some(value) => value
    None => compose_source_group(bm, om, tm)
  }
  let group = if content is Some(value) &&
    !(review_execution &&
    has_execution_evidence(object(value)) &&
    source(value) != source(bg)) {
    value
  } else {
    conflict(Content, Some(bg), Some(og), Some(tg)).unwrap()
  }
  let out : Map[String, Json] = Map([])
  for key, value in object(group) {
    out[key] = value
  }
  fn select(
    field : CellField,
    b : Json?,
    o : Json?,
    t : Json?,
  ) -> Json? raise MergeError {
    match agreed(b, o, t) {
      Some(value) => value
      None => conflict(field, b, o, t)
    }
  }
  for key in keys3(bm, om, tm) {
    if content_keys.contains(key) {
      continue
    }
    if key == "metadata" &&
      bm.get(key) is Some(Object(bmeta)) &&
      om.get(key) is Some(Object(ometa)) &&
      tm.get(key) is Some(Object(tmeta)) {
      let metadata : Map[String, Json] = Map([])
      for name in keys3(bmeta, ometa, tmeta) {
        if select(
            MetadataKey(name),
            bmeta.get(name),
            ometa.get(name),
            tmeta.get(name),
          )
          is Some(v) {
          metadata[name] = v
        }
      }
      out[key] = Json::object(metadata)
    } else if select(Extension(key), bm.get(key), om.get(key), tm.get(key))
      is Some(v) {
      out[key] = v
    }
  }
  Json::object(out)
}

///|
fn compose_cell(b : Json?, o : Json?, t : Json?) -> Json? raise MergeError {
  guard b is Some(Object(bm)) && o is Some(Object(om)) && t is Some(Object(tm)) else {
    return None
  }
  let mut conflicted = false
  let value = compose_existing_cell(bm, om, tm, review_execution=false, (
    _,
    _,
    ours,
    _,
  ) => {
    conflicted = true
    ours
  })
  if conflicted {
    None
  } else {
    Some(value)
  }
}
