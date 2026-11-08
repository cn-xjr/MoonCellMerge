///|
// Structural counters use exact decimal integer tokens, never rounded Double
// comparisons. Arbitrary producer metadata still retains its original numbers.
fn structural_integer(value : Json?, field : String) -> Int32 raise MergeError {
  guard value is Some(Number(_, ..)) else {
    raise Invalid("Expected decimal integer: " + field)
  }
  let text = value.unwrap().stringify()
  if text.is_empty() {
    raise Invalid("Empty integer: " + field)
  }
  let mut result = 0
  for c in text {
    if c < '0' || c > '9' {
      raise Invalid("Use a plain nonnegative decimal integer for " + field)
    }
    let digit = c.to_int() - '0'.to_int()
    if result > (2147483647 - digit) / 10 {
      raise Invalid("Integer exceeds 2147483647: " + field)
    }
    result = result * 10 + digit
  }
  result
}
