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
      "usage: review BASE OURS THEIRS | inspect REVIEW | template REVIEW | resolve BASE OURS THEIRS DECISIONS | merge-to BASE OURS THEIRS OUTPUT | resolve-to BASE OURS THEIRS DECISIONS OUTPUT | git-driver BASE OURS THEIRS",
    )
  }
  if a[1] == "inspect" && a.length() == 3 {
    let r = @merge.restore_review(read(a[2]))
    @stdio.stdout.write(r.to_text() + "\n")
    return if r.conflicts().is_empty() { 0 } else { 1 }
  }
  if a[1] == "template" && a.length() == 3 {
    let r = @merge.restore_review(read(a[2]))
    @stdio.stdout.write(@merge.canonical(r.decision_template()) + "\n")
    return 0
  }
  if (a[1] == "resolve" && a.length() == 6) ||
    (a[1] == "resolve-to" && a.length() == 7) {
    let b = @merge.read_notebook(read(a[2]))
    let o = @merge.read_notebook(read(a[3]))
    let t = @merge.read_notebook(read(a[4]))
    let r = @merge.merge(b, o, t)
    let result = r.apply_decisions(read(a[5]))
    if a[1] == "resolve-to" {
      @fs.write_file(a[6], result + "\n", create_mode=CreateNew, sync=Full)
      @stdio.stdout.write("Created " + Json::string(a[6]).stringify() + "\n")
    } else {
      @stdio.stdout.write(result + "\n")
    }
    return 0
  }
  if a[1] == "merge-to" && a.length() == 6 {
    let r = @merge.merge(
      @merge.read_notebook(read(a[2])),
      @merge.read_notebook(read(a[3])),
      @merge.read_notebook(read(a[4])),
    )
    if !r.conflicts().is_empty() {
      @stdio.stderr.write(r.to_text() + "\n")
      return 1
    }
    let result = r.resolve(Map([]))
    @fs.write_file(a[5], result + "\n", create_mode=CreateNew, sync=Full)
    @stdio.stdout.write("Created " + Json::string(a[5]).stringify() + "\n")
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
