///|
async fn create_staging_directory(parent : @path.Path) -> @path.Path {
  for _ in 0..<8 {
    guard @env.rand(12) is Some(random) else {
      fail("The host cannot generate a temporary notebook name")
    }
    let name = ".mooncellmerge-" + @crypto.bytes_to_hex_string(random)
    let staging = parent.join(@path.Path(name))
    try @fs.mkdir(staging.to_string(), permission=0o700) catch {
      @os_error.OSError(_) as error if error.is_EEXIST() => ()
      error => raise error
    } noraise {
      _ => return staging
    }
  }
  fail(
    "Could not create a unique temporary directory in " +
    inspection_quote(parent.to_string()),
  )
}

///|
async fn publish_notebook(
  path : String,
  data : String,
  replace~ : Bool,
) -> Unit {
  let output = @path.Path(path)
  let name = output.basename()
  let windows = @path.sep == '\\'
  guard !name.is_empty() &&
    name != "." &&
    name != ".." &&
    !path.contains("\u{0}") &&
    !path.has_suffix("/") &&
    !(windows && (path.has_suffix("\\") || name.contains(":"))) else {
    fail("Expected a notebook file path: " + inspection_quote(path))
  }
  // Resolve the existing parent without following a destination symlink.
  let parent = @path.Path(@fs.realpath(output.dirname().to_string()))
  let destination = parent.join(@path.Path(name.to_owned())).to_string()
  if replace {
    guard @fs.kind(destination, follow_symlink=false) is Regular &&
      @fs.can_write(destination) else {
      fail(
        "Git OURS must be a writable regular file: " + inspection_quote(path),
      )
    }
  }
  let staging = create_staging_directory(parent)
  let staging_path = staging.to_string()
  let temporary = staging.join(@path.Path("result.ipynb")).to_string()

  let failure = try {
    {
      let file = @fs.open(
        temporary,
        mode=WriteOnly,
        create_mode=CreateNew,
        permission=if replace { 0o600 } else { 0o644 },
      )
      defer file.close()
      file.write(data)
      file.sync()
    }
    // Use the host's no-replace rename for exports, including concurrent writers.
    @fs.rename(temporary, destination, replace~)
    None
  } catch {
    error => {
      @fs.remove(temporary) catch {
        @os_error.OSError(_) as missing if missing.is_ENOENT() => ()
        cleanup =>
          @stdio.stderr.write(
            "Could not remove staged notebook: " + cleanup.to_string() + "\n",
          )
      }
      Some(error)
    }
  }
  @fs.rmdir(staging_path) catch {
    error =>
      @stdio.stderr.write(
        "Could not remove notebook staging directory: " +
        error.to_string() +
        "\n",
      )
  }
  if failure is Some(error) {
    fail(
      "Could not publish notebook " +
      inspection_quote(path) +
      ": " +
      error.to_string(),
    )
  }
}
