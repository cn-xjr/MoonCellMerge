///|
test "independent notebook metadata edits compose and replay" {
  let b = nb(
    "",
    meta="{\"kernelspec\":{\"name\":\"python3\"},\"owner\":\"team\"}",
  )
  let o = nb(
    "",
    meta="{\"kernelspec\":{\"name\":\"python3\"},\"owner\":\"new-team\"}",
  )
  let t = nb(
    "",
    meta="{\"kernelspec\":{\"name\":\"python3\"},\"owner\":\"team\",\"vendor\":9007199254740993}",
  )
  let r = merge(b, o, t)
  assert_eq(r.conflicts(), [])
  let text = r.resolve(Map([]))
  assert_true(text.contains("new-team") && text.contains("9007199254740993"))
  assert_eq(text, merge(b, t, o).resolve(Map([])))
  assert_eq(restore_review(canonical(r.to_json())).resolve(Map([])), text)
}

///|
test "metadata deletion and null are distinct and nested producers are atomic" {
  let b = nb("", meta="{\"delete\":1,\"other\":0}")
  let text = merge(
    b,
    nb("", meta="{\"other\":0}"),
    nb("", meta="{\"delete\":1,\"other\":null}"),
  ).resolve(Map([]))
  assert_true(!text.contains("delete") && text.contains("null"))
  let r = merge(
    nb("", meta="{\"producer\":{\"a\":1,\"b\":1}}"),
    nb("", meta="{\"producer\":{\"a\":2,\"b\":1}}"),
    nb("", meta="{\"producer\":{\"a\":1,\"b\":2}}"),
  )
  assert_eq(r.conflicts(), ["/notebook/metadata"])
  assert_true(
    try {
      let _ = r.resolve(Map([]))
      false
    } catch {
      _ => true
    },
  )
  assert_eq(merge(b, b, b).resolve(Map([])), canonical(b.value))
}

///|
test "field review chooses metadata keys independently without merging producer objects" {
  let base = nb("", meta="{\"profile/a~b\":1,\"producer\":{\"a\":1,\"b\":1}}")
  let ours = nb("", meta="{\"producer\":{\"a\":2,\"b\":1},\"local\":true}")
  let theirs = nb(
    "",
    meta="{\"profile/a~b\":null,\"producer\":{\"a\":1,\"b\":2},\"vendor\":9007199254740993}",
  )
  let review = merge(base, ours, theirs)
  let profile = "/notebook/metadata/profile~1a~0b"
  let producer = "/notebook/metadata/producer"
  assert_eq(review.conflicts(), ["/notebook/metadata"])
  let evidence = review.field_details()
  assert_eq(evidence.map(item => item.path), [producer, profile])
  assert_eq(evidence[1].kind, "notebook-metadata")
  assert_eq(evidence[1].ours, { "present": false })
  assert_eq(evidence[1].theirs, { "present": true, "value": null })
  let result = review.resolve_fields(
    Map([(profile, Take(Theirs)), (producer, Take(Ours))]),
  )
  assert_eq(
    result,
    canonical(
      nb(
        "",
        meta="{\"profile/a~b\":null,\"producer\":{\"a\":2,\"b\":1},\"local\":true,\"vendor\":9007199254740993}",
      ).value,
    ),
  )
  assert_eq(
    merge(base, theirs, ours).resolve_fields(
      Map([(profile, Take(Ours)), (producer, Take(Theirs))]),
    ),
    result,
  )
  let deleted = review.resolve_fields(
    Map([(profile, Take(Ours)), (producer, Take(Ours))]),
  )
  assert_true(!deleted.contains("profile/a~b"))
  assert_true(deleted.contains("9007199254740993"))
}

///|
test "metadata key decisions replay alongside legacy whole metadata choices" {
  let base = nb("")
  let ours = nb("", meta="{\"profile\":\"one\",\"local\":true}")
  let theirs = nb("", meta="{\"profile\":\"two\",\"remote\":true}")
  let review = merge(base, ours, theirs)
  let root = "/notebook/metadata"
  let path = root + "/profile"
  let choices = Map([(path, Take(Ours))])
  let resolved = review.resolve_fields(choices)
  assert_eq(
    resolved,
    canonical(
      nb("", meta="{\"profile\":\"one\",\"local\":true,\"remote\":true}").value,
    ),
  )
  for
    template in [
      review.field_decision_template(),
      review.compact_decision_template(fields=true),
    ] {
    let doc = object(template)
    doc["choices"] = Json::object(Map([(path, Json::string("ours"))]))
    assert_eq(review.apply_decisions(canonical(template)), resolved)
    doc["choices"] = Json::object(Map([(root, Json::string("ours"))]))
    assert_eq(
      review.apply_decisions(canonical(template)),
      canonical(ours.value),
    )
    doc["choices"] = Json::object(
      Map([(root, Json::string("ours")), (path, Json::string("theirs"))]),
    )
    assert_true(
      try {
        let _ = review.apply_decisions(canonical(template))
        false
      } catch {
        Invalid(_) => true
      },
    )
    doc["choices"] = Json::object(Map([(path, Json::string("ours"))]))
    let changed = merge(base, ours, nb("", meta="{\"profile\":\"three\"}"))
    assert_true(
      try {
        let _ = changed.apply_decisions(canonical(template))
        false
      } catch {
        Invalid(message) => message.contains("stale")
      },
    )
  }
  assert_true(
    try {
      let _ = review.resolve_fields(
        Map([(path, EditSource("wrong field", RequireEmpty))]),
      )
      false
    } catch {
      Invalid(message) => message.contains("cell content conflict")
    },
  )
  assert_eq(review.resolve_fields(choices), resolved)
  assert_eq(review.resolve(Map([(root, Ours)])), canonical(ours.value))
}
