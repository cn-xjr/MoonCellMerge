///|
async fn read(path : String) -> String {
  let file = @fs.open(path[:], mode=ReadOnly)
  defer file.close()
  if file.kind() != Regular || file.size() > 16_000_000L {
    fail("Expected regular file <= 16 MB: " + path)
  }
  let bytes : Array[Byte] = []
  while file.read_some(max_len=65536) is Some(chunk) {
    if bytes.length() + chunk.length() > 16_000_000 {
      fail("Input exceeds 16 MB")
    }
    for byte in chunk {
      bytes.push(byte)
    }
  }
  @utf8.decode(Bytes::from_array(bytes[:])[:])
}

///|
async fn execute() -> Int32 {
  let a = @env.args()
  if a.length() < 2 {
    fail(
      "usage: review BASE OURS THEIRS | resolve BASE OURS THEIRS DECISIONS | git-driver BASE OURS THEIRS",
    )
  }
  if a[1] == "resolve" && a.length() == 6 {
    let b = @merge.read_notebook(read(a[2]))
    let o = @merge.read_notebook(read(a[3]))
    let t = @merge.read_notebook(read(a[4]))
    let r = @merge.merge(b, o, t)
    let doc = @json.parse(
      read(a[5]),
      reject_duplicate_keys=true,
      preserve_number_repr=true,
    )
    guard doc is Object(m) else { fail("Expected decision object") }
    if m.length() < 2 ||
      m.length() > 3 ||
      !m.contains("review") ||
      !m.contains("choices") {
      fail("Decision fields: review, choices, optional order")
    }
    if m.length() == 3 && !m.contains("order") {
      fail("Unknown decision field")
    }
    if @merge.canonical(m["review"]) != @merge.canonical(r.to_json()) {
      fail("Decisions are stale: review inputs do not match current files")
    }
    let _ = @merge.restore_review(@merge.canonical(m["review"]))
    guard m["choices"] is Object(c) else { fail("Expected choices object") }
    let choices : Map[String, @merge.Choice] = Map([])
    for (key, v) in c {
      choices[key] = match v {
        String("base") => Base
        String("ours") => Ours
        String("theirs") => Theirs
        _ => fail("Choice must be base, ours, or theirs")
      }
    }
    let order : Array[String]? = match m.get("order") {
      None => None
      Some(Array(ids)) =>
        Some(
          ids.map(v => {
            guard v is String(s) else { fail("Order must contain cell IDs") }
            s
          }),
        )
      _ => fail("order must be an array")
    }
    @stdio.stdout.write(r.resolve(choices, order?) + "\n")
    return 0
  }
  if a.length() != 5 || (a[1] != "review" && a[1] != "git-driver") {
    fail("Invalid arguments; see README usage")
  }
  let r = @merge.merge(
    @merge.read_notebook(read(a[2])),
    @merge.read_notebook(read(a[3])),
    @merge.read_notebook(read(a[4])),
  )
  if a[1] == "review" {
    @stdio.stdout.write(@merge.canonical(r.to_json()) + "\n")
  } else if r.conflicts().is_empty() {
    @fs.write_file(a[3], r.resolve(Map([])))
  } else {
    @stdio.stderr.write(
      "Unresolved notebook conflicts; OURS retained. Run review to save evidence.\n",
    )
  }
  if r.conflicts().is_empty() {
    0
  } else {
    1
  }
}

///|
#cfg(target="native")
extern "C" fn exit_process(code : Int32) -> Unit = "exit"

///|
#cfg(target="wasm")
#unsafe_skip_stub_check
fn exit_process(code : Int32) -> Unit = "moonbitlang/async" "runtime/exit"

///|
async fn main {
  let code = execute() catch {
    @merge.Invalid(message) => {
      @stdio.stderr.write(message + "\n")
      2
    }
    error => {
      @stdio.stderr.write(error.to_string() + "\n")
      2
    }
  }
  exit_process(code)
}
