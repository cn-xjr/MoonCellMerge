# Initial delivery contract

MoonCellMerge 0.1.0 is an offline library and tool for conservative merging of
nbformat 4.5 notebooks with stable cell IDs. It includes analysis, three-sided
evidence, saved review, input-bound decisions, exclusive result export, a Git
merge driver, packaged downstream consumers and reproducible verification.
It is a source release and has not been uploaded to Mooncakes.

## Reproduce the acceptance workflow

Run from a Git checkout with the pinned compiler/core in README, Git, and tar
(Windows) or unzip (Linux/macOS). JavaScript tests require Node.js. Choose a new
receipt path outside the source tree so it does not mark the checkout dirty:

```text
moon run scripts/acceptance.mbtx portable /absolute/path/new-portable-receipt.json
moon run scripts/acceptance.mbtx native /absolute/path/new-native-receipt.json
```

Native mode includes the portable checks plus actual native tests, the native
consumer executable and native file CLI. Run it on Linux/macOS with a C compiler.
Portable mode does not establish native runtime success. On Windows native
runtime support remains unverified.

The script runs formatting, generated-interface drift checks, strict four-target
compilation, library/consumer tests, actual source-archive consumption, CLI
workflows and real Git merge/conflict/recovery. It checks the unmodified Jupyter
fixture against upstream Git blob `f1f18423e177874825431869c5a7d8d522e0e077` at the
commit recorded in THIRD_PARTY.md. This is fixture identity, not a trust signature.

Only a successful complete run creates the receipt, using exclusive creation.
It records HEAD, whether the checkout was initially dirty, tool version and
targets actually executed. A dirty receipt describes local working files rather
than a reproducible clean commit. A receipt is a local observation, not signed
attestation or proof of another machine's compatibility. An existing output is
never overwritten. Failed runs retain temporary artifacts for diagnosis.

## Demonstrated user workflows

| Workflow | Executable verification |
| --- | --- |
| Parallel analysis-cell changes and conservative same-cell source composition | scripts/e2e.mbtx; source_merge_wbtest.mbt |
| Merge a real code change alongside source and stream reserialization | scripts/corpus_e2e.mbtx; multiline_text_wbtest.mbt |
| Independent producer metadata and insertions into distinct cell gaps | scripts/e2e.mbtx; notebook_metadata_wbtest.mbt; order_merge_wbtest.mbt |
| Delete/edit, stale output evidence and explicit decisions | merge_wbtest.mbt; decisions_wbtest.mbt |
| Read versioned JSON conflict reports in automation | scripts/e2e.mbtx; consumer_test.mbt |
| Resolve only the conflicting cell fields, preserve independent changes, and review custom source safely | scripts/e2e.mbtx; field_review_wbtest.mbt |
| Batch validation continues after malformed and missing files without changing inputs | scripts/e2e.mbtx |
| Preserve rich MIME output and renamed attachments, and review deletion with competing cell moves | scripts/workflows_e2e.mbtx; fixtures/workflows |
| Combine independent cell moves and reject cyclic orders or displaced insertion gaps | scripts/workflows_e2e.mbtx; order_merge_wbtest.mbt |
| Replay compact decisions for large notebooks and reject stale originals without creating output | scripts/large_review_e2e.mbtx; review_document_wbtest.mbt |
| Real Git merge with spaced paths, three index stages, abort and reviewed merge commit | scripts/git_e2e.mbtx |
| Downstream tool uses only the packaged public API | scripts/consumer.mbtx; examples/consumer |

## Independent Jupyter validation

The corpus runner requires Python 3.10 or later and the pinned Jupyter validator.
The drivers and the main acceptance command use the MoonBit toolchain as before.

```text
python -m pip install nbformat==5.11.1
moon run scripts/corpus_e2e.mbtx wasm
moon run scripts/corpus_e2e.mbtx native
```

Set `CELLMERGE_PYTHON` to a Python executable in an isolated environment if
needed. Native mode runs the native file CLI on Linux/macOS. The corpus is
vendored, so the runner reads local fixture files and needs no network when
the validator and MoonBit dependencies are installed.

The runner checks each original against its pinned Git blob. For both nbformat
4.5 originals, MoonCellMerge produces a clean merge and a resolved merge. The
runner compares each whole notebook against the expected edits, including cell
order and untouched execution output. It passes the raw export JSON to
`nbformat.validate` and checks that the validator rejects invalid tag metadata.
The older JupyterLab rich MIME sample passes Jupyter's 4.4 schema and exercises
MoonCellMerge's unsupported-version diagnostic. The check reads stored output
without executing any notebook cells.

CI runs the Wasm corpus on Windows, Linux and macOS, plus the native corpus on
Linux and macOS. The corpus jobs must pass before the driver bundle is uploaded.
Fixture origins and notices are recorded in [THIRD_PARTY.md](../THIRD_PARTY.md).

## CI results

CI uses this same acceptance command: portable mode on Windows and native mode
on Linux/macOS. Each successful job leaves acceptance-receipt.json in its runner
checkout; no receipt is committed into the source tree or published as a package.
The receipt and detailed command output are printed in the job log.

The optional final argument to the acceptance command names a fresh driver
bundle directory. For example:

```text
moon run scripts/acceptance.mbtx portable new-receipt.json new-driver-bundle
```

The bundle uses the same Wasm and notebook input bytes exercised by the real Git
tests. It includes the quickstart, tested MoonRun version, licenses and a copy of
the acceptance receipt. Successful `main` jobs upload their bundles to GitHub
Actions as `mooncellmerge-driver-Linux`, `mooncellmerge-driver-macOS`, and
`mooncellmerge-driver-Windows`. The OS suffix identifies the job that ran the
tests. [Use the downloaded driver](git-quickstart.md).

The acceptance log reports the test count per backend; the independently
compiled package consumer also runs tests and an executable.
CI runs portable workflows on three OSes and
actual native workflows on Linux/macOS. Inspect the exact HEAD's Actions run;
an older green revision does not establish a newer one passes.

## Boundaries and remaining work

- The reader validates the merge-relevant structural subset, not the full
  Jupyter JSON Schema. Unknown metadata/outputs are retained as opaque JSON.
- The source composer handles bounded disjoint contiguous edits and multiple
  changes separated by unique, ordered anchors. Ambiguous edits and competing
  cell moves remain explicit conflicts.
- Retained cell moves compose when their pair constraints agree. Each window
  changed differently by both branches is bounded to 512 cells. Insertions
  require their original gap to survive the resulting order.
- Code is not executed; choosing retained output does not certify freshness.
- No legacy cell-ID inference, notebook trust/signatures, browser UI or editor
  extension is included. There is no performance advantage claim.
- Exclusive result exports protect existing files. A new file can remain partial
  after I/O failure. Git's temporary OURS uses a normal write; original Git
  versions are the recovery source for interrupted writes.

These limits define the initial delivery. Further work should improve adoption
and correctness against real notebooks, without weakening conflict visibility or
silently discarding unsupported data.
