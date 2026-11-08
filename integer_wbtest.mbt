///|
test "structural numbers reject floating-point rounding and alternate tokens" {
  let raw = canonical(nb(cell("a", "x")).value)
  for value in ["4.0000000000000000000001", "4.0", "4e0", "-0", "2147483648"] {
    let modified = raw.replace(
      old="\"nbformat\":4",
      new="\"nbformat\":" + value,
    )
    assert_true(
      try {
        let _ = read_notebook(modified)
        false
      } catch {
        _ => true
      },
    )
  }
  for
    value in [
      "0.00000000000000000000001", "1.00000000000000000001", "2147483647.00000001",
      "2147483648", "-0", "1e0",
    ] {
    let modified = raw.replace(
      old="\"execution_count\":null",
      new="\"execution_count\":" + value,
    )
    assert_true(
      try {
        let _ = read_notebook(modified)
        false
      } catch {
        _ => true
      },
    )
  }
  for value in ["0", "2147483647"] {
    let n = read_notebook(
      raw.replace(
        old="\"execution_count\":null",
        new="\"execution_count\":" + value,
      ),
    )
    assert_eq(merge(n, n, n).conflicts(), [])
  }
}

///|
test "integer rejection does not constrain producer numbers or recovery" {
  let n = nb("", meta="{\"producer\":4.0000000000000000000001}")
  assert_true(
    merge(n, n, n).resolve(Map([])).contains("4.0000000000000000000001"),
  )
  let raw = canonical(n.value).replace(
    old="\"nbformat_minor\":5",
    new="\"nbformat_minor\":5.000000000000001",
  )
  assert_true(
    try {
      let _ = read_notebook(raw)
      false
    } catch {
      _ => true
    },
  )
  assert_eq(restore_review(canonical(merge(n, n, n).to_json())).conflicts(), [])
}
