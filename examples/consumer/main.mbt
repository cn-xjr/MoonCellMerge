///|
fn main {
  let notebook = "{\"nbformat\":4,\"nbformat_minor\":5,\"metadata\":{},\"cells\":[]}"
  let n = @cells.read_notebook(notebook) catch { _ => panic() }
  let review = @cells.merge(n,n,n) catch { _ => panic() }
  let restored = @cells.restore_review(@cells.canonical(review.to_json())) catch { _ => panic() }
  let result = restored.apply_decisions(@cells.canonical(restored.decision_template())) catch { _ => panic() }
  println("MoonCellMerge independent consumer: " + result)
}
