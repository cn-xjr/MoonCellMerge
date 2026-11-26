///|
test "resolving only divergent source keeps the other branch's metadata" {
  let b = metadata_cell("original", "{}")
  let o = metadata_cell("ours", "{}")
  let t = metadata_cell("theirs", "{\"reviewer\":\"team\"}")
  let r = merge(b, o, t)
  let path = "/cells/a/content"
  assert_eq(r.conflicts(), ["/cells/a"])
  let details = r.field_details()
  assert_eq(details.map(c => c.path), [path])
  assert_true(!canonical(details[0].ours).contains("metadata"))
  let text = r.resolve_fields(Map([(path, Take(Ours))]))
  assert_eq(
    text,
    canonical(metadata_cell("ours", "{\"reviewer\":\"team\"}").value),
  )
  assert_eq(r.resolve({ "/cells/a": Ours }), canonical(o.value))
  let swapped = merge(b, t, o)
  assert_eq(swapped.resolve_fields(Map([(path, Take(Theirs))])), text)
  let doc = object(r.field_decision_template())
  doc["choices"] = Json::object(Map([(path, Json::string("ours"))]))
  assert_eq(r.apply_decisions(canonical(Json::object(doc))), text)
  let stale = merge(b, o, metadata_cell("theirs", "{\"reviewer\":\"new\"}"))
  assert_true(
    try {
      let _ = stale.apply_decisions(canonical(Json::object(doc)))
      false
    } catch {
      Invalid(message) => message.contains("stale")
    },
  )
}

///|
test "cell metadata and extension decisions escape keys and distinguish absence from null" {
  fn n(meta : String, field : Double) -> Notebook raise MergeError {
    let m = object(metadata_cell("same", meta).value)
    guard m["cells"] is Array([Object(c)]) else {
      raise Invalid("Expected test cell")
    }
    c["extra/key"] = Json::number(field)
    read_notebook(canonical(Json::object(m)))
  }
  let r = merge(
    n("{\"a/b~c\":1}", 0),
    n("{\"local\":true}", 1),
    n("{\"a/b~c\":null,\"other\":true}", 2),
  )
  let meta = "/cells/a/metadata/a~1b~0c"
  let ext = "/cells/a/fields/extra~1key"
  assert_true(r.field_details().map(c => c.path).contains(meta))
  assert_true(r.field_details().map(c => c.path).contains(ext))
  let text = r.resolve_fields(Map([(meta, Take(Theirs)), (ext, Take(Ours))]))
  assert_true(text.contains("\"a/b~c\":null"))
  assert_true(text.contains("\"extra/key\":1"))
  assert_true(
    text.contains("\"local\":true") && text.contains("\"other\":true"),
  )
  let deleted = r.resolve_fields(Map([(meta, Take(Ours)), (ext, Take(Ours))]))
  assert_true(!deleted.contains("a/b~c"))
  assert_true(
    try {
      let _ = r.resolve_fields(
        Map([(meta, EditSource("x", RequireEmpty)), (ext, Take(Ours))]),
      )
      false
    } catch {
      Invalid(message) => message.contains("cell content conflict")
    },
  )
}

///|
test "custom source requires deliberate clearing of saved code evidence" {
  let output = "[{\"output_type\":\"stream\",\"name\":\"stdout\",\"text\":\"saved run\"}]"
  let b = metadata_cell("old", "{}")
  let o = metadata_cell("ours", "{\"keep\":true}")
  let t = metadata_cell("theirs", "{}", outputs=output)
  let r = merge(b, o, t)
  let path = "/cells/a/content"
  assert_true(
    try {
      let _ = r.resolve_fields(Map([(path, EditSource("both", RequireEmpty))]))
      false
    } catch {
      Invalid(message) => message.contains("explicit execution clearing")
    },
  )
  assert_true(
    r.resolve_fields(Map([(path, Take(Theirs))])).contains("saved run"),
  )
  let merged = r.resolve_fields(
    Map([(path, EditSource("both", ClearExecution))]),
  )
  assert_eq(merged, canonical(metadata_cell("both", "{\"keep\":true}").value))
  let doc = object(r.field_decision_template())
  doc["choices"] = Json::object(
    Map([
      (
        path,
        Json::object({
          "source": Json::string("both"),
          "execution": Json::string("clear"),
        }),
      ),
    ]),
  )
  assert_eq(r.apply_decisions(canonical(Json::object(doc))), merged)
  assert_eq(
    restore_review(canonical(r.to_json())).resolve_fields(
      Map([(path, EditSource("both", ClearExecution))]),
    ),
    merged,
  )
}

///|
test "field decisions reject bad paths and source edits and leave the review reusable" {
  let r = merge(
    nb(cell("a", "base")),
    nb(cell("a", "ours")),
    nb(cell("a", "theirs")),
  )
  let original = canonical(r.field_conflict_report())
  let doc = object(r.field_decision_template())
  for
    choices in [
      Json::empty_object(),
      Json::object({ "/cells/a": Json::string("ours") }),
      Json::object({
        "/cells/a/content": Json::object({ "source": Json::string("manual") }),
      }),
      Json::object({
        "/cells/a/content": Json::object({
          "source": Json::string("manual"),
          "execution": Json::string("keep"),
        }),
      }),
    ] {
    doc["choices"] = choices
    assert_true(
      try {
        let _ = r.apply_decisions(canonical(Json::object(doc)))
        false
      } catch {
        Invalid(_) => true
      },
    )
  }
  assert_eq(canonical(r.field_conflict_report()), original)
  assert_eq(
    r.resolve_fields({ "/cells/a/content": EditSource("manual", RequireEmpty) }),
    canonical(nb(cell("a", "manual")).value),
  )
}

///|
test "field review also surfaces an unopposed source change with a retained count" {
  let b = nb(
    cell("a", "old").replace(
      old="execution_count\":null",
      new="execution_count\":0",
    ),
  )
  let o = nb(
    cell("a", "new").replace(
      old="execution_count\":null",
      new="execution_count\":0",
    ),
  )
  let t = nb(
    cell("a", "old")
    .replace(old="\"metadata\":{}", new="\"metadata\":{\"team\":true}")
    .replace(old="execution_count\":null", new="execution_count\":0"),
  )
  let r = merge(b, o, t)
  let path = "/cells/a/content"
  assert_eq(r.field_details().map(c => c.path), [path])
  let text = r.resolve_fields(Map([(path, Take(Ours))]))
  assert_true(
    text.contains("\"execution_count\":0") && text.contains("\"team\":true"),
  )
}

///|
test "custom source refuses attachment-bearing cells and delete-edit stays whole-cell" {
  fn note(text : String) -> Notebook raise MergeError {
    nb(
      "{\"id\":\"a\",\"cell_type\":\"markdown\",\"source\":" +
      Json::string(text).stringify() +
      ",\"attachments\":{\"chart.png\":{\"image/png\":\"AA==\"}},\"metadata\":{}}",
    )
  }
  let b = note("original")
  let o = note("ours")
  let t = note("theirs")
  let r = merge(b, o, t)
  assert_true(
    try {
      let _ = r.resolve_fields({
        "/cells/a/content": EditSource("combined", RequireEmpty),
      })
      false
    } catch {
      Invalid(message) => message.contains("attachments")
    },
  )
  assert_eq(
    r.resolve_fields({ "/cells/a/content": Take(Ours) }),
    canonical(o.value),
  )
  let deletion = merge(b, nb(""), t)
  assert_eq(deletion.field_details().map(c => c.path), [
    "/cells/a", "/cell-order",
  ])
  assert_eq(
    deletion.resolve_fields({ "/cells/a": Take(Theirs) }, order=["a"]),
    canonical(t.value),
  )
}
