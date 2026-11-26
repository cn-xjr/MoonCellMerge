///|
const MoveWindowLimit = 512

///|
fn positions(ids : Array[String]) -> Map[String, Int32] {
  let result : Map[String, Int32] = Map([])
  for i, key in ids {
    result[key] = i
  }
  result
}

///|
// A pair keeps its base order unless either branch reverses it. The resulting
// complete set of pair constraints has a unique order exactly when each cell
// has a distinct predecessor count. If so, remove the zero-count cell and
// apply the same argument to the rest. A cycle forces a repeated count.
fn order_move_window(
  base : ArrayView[String],
  ours : ArrayView[Int32],
  theirs : ArrayView[Int32],
) -> Array[String]? {
  let n = base.length()
  if n > MoveWindowLimit {
    return None
  }
  let predecessors = Array::make(n, 0)
  for i in 0..<n {
    for j in (i + 1)..<n {
      if ours[i] > ours[j] || theirs[i] > theirs[j] {
        predecessors[i] += 1
      } else {
        predecessors[j] += 1
      }
    }
  }
  let result = Array::make(n, "")
  for i, rank in predecessors {
    if result[rank] != "" {
      return None
    }
    result[rank] = base[i]
  }
  Some(result)
}

///|
fn compose_moves(
  base : Array[String],
  ours : Array[String],
  theirs : Array[String],
) -> Array[String]? {
  if ours == theirs || theirs == base {
    return Some(ours)
  }
  if ours == base {
    return Some(theirs)
  }
  let op = positions(ours)
  let tp = positions(theirs)
  let left = base.map(key => op[key])
  let right = base.map(key => tp[key])
  let result : Array[String] = []
  let mut start = 0
  let mut furthest = 0
  let mut ours_changed = false
  let mut theirs_changed = false
  let mut agree = true
  for i in 0..<base.length() {
    furthest = furthest.max(left[i]).max(right[i])
    ours_changed = ours_changed || left[i] != i
    theirs_changed = theirs_changed || right[i] != i
    agree = agree && left[i] == right[i]
    if furthest == i {
      // Each branch has exactly the same IDs in this prefix. Nothing can move
      // across the boundary, so the following window is independent.
      let end = i + 1
      let window = if agree || !theirs_changed {
        ours[start:end]
      } else if !ours_changed {
        theirs[start:end]
      } else {
        guard order_move_window(
            base[start:end],
            left[start:end],
            right[start:end],
          )
          is Some(order) else {
          return None
        }
        order[:]
      }
      for key in window {
        result.push(key)
      }
      start = end
      ours_changed = false
      theirs_changed = false
      agree = true
    }
  }
  Some(result)
}
