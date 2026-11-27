///|
async test "concurrent exports publish exactly one complete file" {
  let dir = @fs.tmpdir(prefix="cellmerge-publish")
  let path = dir + "/notebook 结果.ipynb"
  let left = "left\n".repeat(65_537)
  let right = "right\n".repeat(65_537)
  async fn attempt(data : String) -> Bool {
    try {
      publish_notebook(path, data, replace=false)
      true
    } catch {
      error => {
        assert_true(error.to_string().contains("Could not publish notebook"))
        false
      }
    }
  }
  let (a, b) = @async.with_task_group(group => {
    let a = group.spawn(() => attempt(left))
    let b = group.spawn(() => attempt(right))
    (a.wait(), b.wait())
  })
  assert_true(a != b)
  assert_eq(@fs.read_file(path).text(), if a { left } else { right })
  assert_eq(@fs.readdir(dir, include_hidden=true), ["notebook 结果.ipynb"])
  @fs.remove(path)
  @fs.rmdir(dir)
}

///|
async test "publication failure preserves the destination and permits retry" {
  let dir = @fs.tmpdir(prefix="cellmerge-publish")
  let path = dir + "/occupied.ipynb"
  @fs.mkdir(path)
  @fs.write_file(path + "/marker", "existing directory")
  let blocked = try {
    publish_notebook(path, "staged notebook", replace=false)
    false
  } catch {
    _ => true
  }
  assert_true(blocked)
  assert_eq(@fs.read_file(path + "/marker").text(), "existing directory")
  assert_eq(@fs.readdir(dir, include_hidden=true), ["occupied.ipynb"])
  @fs.remove(path + "/marker")
  @fs.rmdir(path)
  publish_notebook(path, "retry succeeded", replace=false)
  assert_eq(@fs.read_file(path).text(), "retry succeeded")
  @fs.remove(path)
  @fs.rmdir(dir)
}

///|
async test "Git publication refuses links and preserves their target" {
  if @path.sep == '\\' {
    return
  }
  let dir = @fs.tmpdir(prefix="cellmerge-publish")
  let original = dir + "/original.ipynb"
  let ours = dir + "/ours.ipynb"
  @fs.write_file(original, "old notebook")
  @fs.symlink(ours, target=@fs.realpath(original))
  let blocked = try {
    publish_notebook(ours, "new notebook", replace=true)
    false
  } catch {
    _ => true
  }
  assert_true(blocked)
  assert_eq(@fs.kind(ours, follow_symlink=false), @fs.SymLink)
  assert_eq(@fs.read_file(original).text(), "old notebook")
  @fs.remove(ours)
  @fs.remove(original)
  @fs.rmdir(dir)
}
