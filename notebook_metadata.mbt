///|
const NotebookMetadataPath = "/notebook/metadata"

///|
// Producer-owned values stay atomic, even when they are objects.
fn merge_metadata_keys(
  base : Map[String, Json],
  ours : Map[String, Json],
  theirs : Map[String, Json],
  conflict : (String, Json?, Json?, Json?) -> Json? raise MergeError,
) -> Json raise MergeError {
  let out : Map[String, Json] = Map([])
  for key in keys3(base, ours, theirs) {
    let b = base.get(key)
    let o = ours.get(key)
    let t = theirs.get(key)
    let value = match agreed(b, o, t) {
      Some(chosen) => chosen
      None => conflict(key, b, o, t)
    }
    if value is Some(payload) {
      out[key] = payload
    }
  }
  Json::object(out)
}

///|
fn compose_notebook_metadata(
  b : Json?,
  o : Json?,
  t : Json?,
) -> Json? raise MergeError {
  guard b is Some(Object(bm)) && o is Some(Object(om)) && t is Some(Object(tm)) else {
    return None
  }
  let mut conflicted = false
  let metadata = merge_metadata_keys(bm, om, tm, (_, _, _, _) => {
    conflicted = true
    None
  })
  if conflicted {
    None
  } else {
    Some(metadata)
  }
}
