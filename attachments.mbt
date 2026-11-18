///|
// Payloads stay opaque: this validates the container, never decodes an image.
fn validate_attachments(value : Json?, path : String) -> Unit raise MergeError {
  match value {
    None => ()
    Some(Object(files)) =>
      for (name, bundle) in files {
        guard bundle is Object(_) else {
          raise Invalid(
            "Expected attachment MIME object at " +
            path +
            "/" +
            name.replace_all(old="~", new="~0").replace_all(old="/", new="~1"),
          )
        }
      }
    _ => raise Invalid("Expected attachments object at " + path)
  }
}
