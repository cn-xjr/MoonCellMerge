///|
const ReviewLimit = 16_000_000

///|
fn Review::embedded_review(self : Review) -> Json {
  Json::object({
    "version": Json::number(1),
    "base": Json::string(self.base.raw),
    "ours": Json::string(self.ours.raw),
    "theirs": Json::string(self.theirs.raw),
    "conflicts": Json::array(self.conflicts.map(Json::string)),
  })
}

///|
fn notebook_digest(raw : String) -> Json {
  let bytes = @utf16.encode(raw[:], bom=false, endianness=Little)
  Json::string(@crypto.bytes_to_hex_string(@crypto.sha256(bytes)))
}

///|
/// A version 2 review binds each input by its SHA-256 digest over the
/// exact UTF-16LE text without an added BOM. Keep the originals for replay.
pub fn Review::compact_review(self : Review) -> Json {
  Json::object({
    "version": Json::number(2),
    "sha256_utf16le": Json::object({
      "base": notebook_digest(self.base.raw),
      "ours": notebook_digest(self.ours.raw),
      "theirs": notebook_digest(self.theirs.raw),
    }),
    "conflicts": Json::array(self.conflicts.map(Json::string)),
  })
}

///|
/// Small reviews embed the inputs in version 1. When their total length
/// exceeds one million UTF-16 units, use version 2 with input digests.
pub fn Review::to_json(self : Review) -> Json {
  if self.base.raw.length() + self.ours.raw.length() + self.theirs.raw.length() >
    1_000_000 {
    self.compact_review()
  } else {
    self.embedded_review()
  }
}

///|
fn parse_review_document(text : String) -> Json raise MergeError {
  if text.length() > ReviewLimit {
    raise Invalid("Review exceeds 16 million UTF-16 units")
  }
  @json.parse(
    text,
    max_nesting_depth=64,
    reject_duplicate_keys=true,
    preserve_number_repr=true,
  ) catch {
    _ => raise Invalid("Invalid review JSON")
  }
}

///|
fn review_version(doc : Json) -> Int32 raise MergeError {
  structural_integer(object(doc).get("version"), "review version")
}

///|
fn Review::matches_binding(self : Review, doc : Json) -> Bool raise MergeError {
  match review_version(doc) {
    1 => same_json(doc, self.embedded_review())
    2 => same_json(doc, self.compact_review())
    _ => raise Invalid("Unsupported review version")
  }
}

///|
/// Replay an embedded review with the supplied original texts in the document.
pub fn restore_review(text : String) -> Review raise MergeError {
  let doc = parse_review_document(text)
  match review_version(doc) {
    1 => ()
    2 => raise Invalid("Compact review requires BASE OURS THEIRS for replay")
    _ => raise Invalid("Unsupported review version")
  }
  let m = object(doc)
  fn get(key : String) -> String raise MergeError {
    guard m.get(key) is Some(String(s)) else {
      raise Invalid("Missing review input " + key)
    }
    s
  }
  let r = merge(
    read_notebook(get("base")),
    read_notebook(get("ours")),
    read_notebook(get("theirs")),
  )
  if !r.matches_binding(doc) {
    raise Invalid("Review fields/version/conflicts do not match replay")
  }
  r
}

///|
/// Recompute and verify a compact review against the original inputs in order.
pub fn restore_compact_review(
  text : String,
  base : Notebook,
  ours : Notebook,
  theirs : Notebook,
) -> Review raise MergeError {
  let doc = parse_review_document(text)
  if review_version(doc) != 2 {
    raise Invalid("Expected a version 2 compact review")
  }
  let r = merge(base, ours, theirs)
  if !r.matches_binding(doc) {
    raise Invalid(
      "Compact review is stale: inputs or conflicts do not match replay",
    )
  }
  r
}
