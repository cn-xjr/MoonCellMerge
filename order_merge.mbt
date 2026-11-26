///|
// Both branches must contain every retained base cell for movement inference.
// Insertions have to keep their original pair of adjacent anchors.
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
  let old_ours = project(ours, base_ids, retained)
  let old_theirs = project(theirs, base_ids, retained)
  if old_ours.length() != old.length() || old_theirs.length() != old.length() {
    return None
  }
  guard compose_moves(old, old_ours, old_theirs) is Some(ordered) else {
    return None
  }
  let successor : Map[String, String] = Map([])
  let mut previous = ""
  for key in ordered {
    successor[previous] = key
    previous = key
  }
  fn slots(
    ids : Array[String],
    old_ids : Map[String, Bool],
    kept : Map[String, Json],
  ) -> Map[String, Array[String]]? {
    let out : Map[String, Array[String]] = Map([])
    let mut anchor = ""
    for key in ids {
      if !kept.contains(key) {
        continue
      }
      if old_ids.contains(key) {
        if out.contains(anchor) && successor.get(anchor) != Some(key) {
          return None
        }
        anchor = key
      } else {
        if !out.contains(anchor) {
          out[anchor] = []
        }
        out[anchor].push(key)
      }
    }
    if out.contains(anchor) && successor.contains(anchor) {
      return None
    }
    Some(out)
  }
  guard slots(ours, base_ids, retained) is Some(os) &&
    slots(theirs, base_ids, retained) is Some(ts) else {
    return None
  }
  let anchors = [""]
  for key in ordered {
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
