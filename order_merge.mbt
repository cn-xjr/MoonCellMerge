///|
// Only infer insert/delete composition when every surviving base cell appears
// in both branches in its original order. Moves and delete/edit decisions stay
// explicit. Insertions in the same surviving-base gap must agree exactly.
fn compose_order(
  b : Json,
  o : Json,
  t : Json,
  retained : Map[String, Json],
) -> Array[String]? raise MergeError {
  let base = cells(b).map(id)
  let ours = cells(o).map(id)
  let theirs = cells(t).map(id)
  let base_ids : Map[String, Bool] = Map([])
  for key in base {
    base_ids[key] = true
  }
  let old = base.filter(k => retained.contains(k))
  fn project(
    ids : Array[String],
    old_ids : Map[String, Bool],
    kept : Map[String, Json],
  ) -> Array[String] {
    ids.filter(k => old_ids.contains(k) && kept.contains(k))
  }
  if old != project(ours, base_ids, retained) ||
    old != project(theirs, base_ids, retained) {
    return None
  }
  fn slots(
    ids : Array[String],
    old_ids : Map[String, Bool],
    kept : Map[String, Json],
  ) -> Map[String, Array[String]] {
    let out : Map[String, Array[String]] = Map([])
    let mut anchor = ""
    for key in ids {
      if !kept.contains(key) {
        continue
      }
      if old_ids.contains(key) {
        anchor = key
      } else {
        if !out.contains(anchor) {
          out[anchor] = []
        }
        out[anchor].push(key)
      }
    }
    out
  }
  let os = slots(ours, base_ids, retained)
  let ts = slots(theirs, base_ids, retained)
  let anchors = [""]
  for key in old {
    anchors.push(key)
  }
  let result : Array[String] = []
  let seen : Map[String, Bool] = Map([])
  for anchor in anchors {
    if anchor != "" {
      result.push(anchor)
      seen[anchor] = true
    }
    let oa = os.get(anchor).unwrap_or([])
    let ta = ts.get(anchor).unwrap_or([])
    let inserted = if oa == ta || ta.is_empty() {
      oa
    } else if oa.is_empty() {
      ta
    } else {
      return None
    }
    for key in inserted {
      if seen.contains(key) {
        return None
      }
      seen[key] = true
      result.push(key)
    }
  }
  if result.length() == retained.length() {
    Some(result)
  } else {
    None
  }
}
