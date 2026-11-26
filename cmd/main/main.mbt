///|
async fn read(path : String) -> String {
  let file = @fs.open(path[:], mode=ReadOnly)
  defer file.close()
  let size = file.size()
  if file.kind() != Regular || size > 16_000_000L {
    fail("Expected regular file <= 16 MB: " + path)
  }
  let bytes = @buffer.Buffer(size_hint=size.to_int())
  while file.read_some(max_len=65536) is Some(chunk) {
    if bytes.length() + chunk.length() > 16_000_000 {
      fail("Input exceeds 16 MB")
    }
    bytes.write_bytesview(chunk)
  }
  @utf8.decode(bytes.to_bytes()[:])
}

///|
async fn read_review(args : Array[String]) -> @merge.Review {
  let text = read(args[2])
  if args.length() == 6 {
    @merge.restore_compact_review(
      text,
      @merge.read_notebook(read(args[3])),
      @merge.read_notebook(read(args[4])),
      @merge.read_notebook(read(args[5])),
    )
  } else {
    @merge.restore_review(text)
  }
}

///|
async fn execute() -> Int32 {
  let a = @env.args()
  if a.length() < 2 {
    fail(
      "usage: validate NOTEBOOK... | review or review-compact BASE OURS THEIRS | inspect, inspect-json, inspect-fields, template or template-fields REVIEW [BASE OURS THEIRS] | resolve BASE OURS THEIRS DECISIONS | merge-to BASE OURS THEIRS OUTPUT | resolve-to BASE OURS THEIRS DECISIONS OUTPUT | git-driver BASE OURS THEIRS",
    )
  }
  if a[1] == "validate" && a.length() >= 3 {
    let mut invalid = false
    for i in 2..<a.length() {
      let path = a[i]
      let diagnostic : String? = try {
        let _ = @merge.read_notebook(read(path))
        None
      } catch {
        @merge.Invalid(message) => Some(message)
        error => Some(error.to_string())
      }
      let result = match diagnostic {
        None =>
          Json::object({
            "path": Json::string(path),
            "valid": Json::boolean(true),
          })
        Some(message) => {
          invalid = true
          Json::object({
            "path": Json::string(path),
            "valid": Json::boolean(false),
            "diagnostic": Json::string(message),
          })
        }
      }
      @stdio.stdout.write(@merge.canonical(result) + "\n")
    }
    return if invalid { 2 } else { 0 }
  }
  if ["inspect", "inspect-json", "inspect-fields"].contains(a[1]) &&
    (a.length() == 3 || a.length() == 6) {
    let r = read_review(a)
    let report = match a[1] {
      "inspect-json" => @merge.canonical(r.conflict_report())
      "inspect-fields" => @merge.canonical(r.field_conflict_report())
      _ => r.to_text()
    }
    @stdio.stdout.write(report + "\n")
    return if r.conflicts().is_empty() { 0 } else { 1 }
  }
  if ["template", "template-fields"].contains(a[1]) &&
    (a.length() == 3 || a.length() == 6) {
    let r = read_review(a)
    let fields = a[1] == "template-fields"
    let template = if a.length() == 6 {
      r.compact_decision_template(fields~)
    } else if fields {
      r.field_decision_template()
    } else {
      r.decision_template()
    }
    @stdio.stdout.write(@merge.canonical(template) + "\n")
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
  if a.length() != 5 ||
    !["review", "review-compact", "git-driver"].contains(a[1]) {
    fail("Invalid arguments; see README usage")
  }
  let r = @merge.merge(
    @merge.read_notebook(read(a[2])),
    @merge.read_notebook(read(a[3])),
    @merge.read_notebook(read(a[4])),
  )
  if a[1] == "review" {
    @stdio.stdout.write(@merge.canonical(r.to_json()) + "\n")
  } else if a[1] == "review-compact" {
    @stdio.stdout.write(@merge.canonical(r.compact_review()) + "\n")
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
