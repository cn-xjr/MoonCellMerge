///|
// Notebook metadata has producer-owned top-level keys. Merge only independent
// keys; nested objects remain atomic so kernelspec/language_info cannot become
// a synthetic combination of incompatible producer settings.
fn compose_notebook_metadata(b : Json?, o : Json?, t : Json?) -> Json? {
  guard b is Some(Object(bm)) && o is Some(Object(om)) && t is Some(Object(tm)) else {
    return None
  }
  let conflicts : Array[String] = []
  let out : Map[String, Json] = Map([])
  for key in keys3(bm, om, tm) {
    if pick(key, bm.get(key), om.get(key), tm.get(key), Map([]), conflicts)
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
