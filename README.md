# MoonCellMerge

Conservative cell-ID-aware three-way Jupyter notebook merge and review in MoonBit.
For teams maintaining notebooks in Git and developers building notebook tools.

## Implemented scope

Source version 0.1.0; not published to Mooncakes. nbformat 4.5 with unique legal
cell IDs; code, Markdown and raw cells. Independent cell edits merge. Different
edits to one cell conflict atomically. Single-sided insert/delete/move works;
incompatible orders require an explicit complete retained-ID array. Delete/edit
conflicts retain evidence. Changed source with nonempty outputs requires explicit
whole-cell acknowledgment. Outputs are never silently cleared or certified current.

Unknown JSON fields, metadata, attachments and output payloads are retained as
opaque values. Numbers retain exact JSON spellings, including integers beyond
2^53. Duplicate keys fail. Object keys sort deterministically; whitespace and
original key order are not retained. Reader validation covers the structural
subset needed by merging, not the entire nbformat JSON Schema. No kernel runs.

Limits: 4 million UTF-16 units per notebook, 1 million combined merge input units,
10,000 cells, JSON depth 64. Unsupported format versions/types and invalid IDs
are rejected. No legacy ID guessing, notebook trust signatures, DIB conversion,
source-line merging or proof of execution-result freshness is implemented.

## Run

Pinned compiler/core: `0.10.20+65efd5b93`, official stable feed checked 2026-11-07.
File CLI supports Wasm and native (C compiler required). Pure library tests target
Wasm, Wasm-GC, JavaScript and native. Git and MoonBit are the only demo prerequisites.

```text
moon update
moon run scripts/e2e.mbtx wasm
moon run cmd/main -- review BASE.ipynb OURS.ipynb THEIRS.ipynb
```

E2E derives branches from an unmodified real Jupyter fixture, then checks clean
merge, conflicts, resolution, stale decisions, malformed input and recovery.
It prints and retains its isolated temporary directory, including merged.ipynb.
No private service, database, publisher account or Python runtime is needed.

`review` prints an envelope with version, all three exact input texts and conflict
paths. Save stdout. Exit codes: 0 clean, 1 conflicts, 2 invalid input/I/O. Build a
decision JSON object containing `review` (the entire saved envelope), `choices`
(each conflict path mapped to `base`, `ours` or `theirs`), and, for `/cell-order`,
an `order` array listing every retained ID exactly once. Clean reviews use empty
choices. Missing, duplicate, unknown or stale decisions fail.

```text
moon run cmd/main -- resolve BASE.ipynb OURS.ipynb THEIRS.ipynb DECISIONS.json
```

Resolved JSON goes to stdout. Do not redirect onto an input file. Review/resolve
do not write destinations. Whole-cell selection acknowledges all its values,
including potentially stale output; it does not establish scientific correctness.

## Git driver

Configure the consuming repository locally (replace the absolute checkout path):

```text
moon build --target wasm cmd/main
git config merge.cellmerge.name "MoonCellMerge notebook merge"
git config merge.cellmerge.driver 'moonrun /absolute/path/MoonCellMerge/_build/wasm/debug/build/cmd/main/main.wasm -- git-driver %O %A %B'
```

Add `*.ipynb merge=cellmerge` to its .gitattributes. Quote paths containing spaces.
Only a clean merge writes Git's temporary OURS file; conflicts leave it unchanged
and exit 1. Use review/resolve to resolve conflicts, then stage the reviewed file.
The initial driver uses a normal file write, not a durable atomic rename; use
Git's original versions to recover from an interrupted write.

## Library and adoption

Import `cn-xjr/mooncellmerge` in moon.pkg; until publication use a local moon.work
containing this checkout and your separate module. API: `read_notebook`, `merge`,
`Review::conflicts`, `Review::to_json`, `restore_review`, `Review::resolve`,
`Choice`, `MergeError`, `canonical`. Notebook/Review internals are private.
See pkg.generated.mbti. Returned conflict arrays are copies.

Use cases: parallel edits to separate analysis cells; teaching-repository upstream
sync with a single-sided cell move; deletion versus editing requiring explicit
whole-cell review. The first milestone includes CLI, review replay and Git use.

```text
moon fmt --check
moon info
moon check --target all --deny-warn
moon test --target wasm --deny-warn
moon test --target wasm-gc --deny-warn
moon test --target js --deny-warn
moon test --target native --deny-warn
moon run scripts/e2e.mbtx wasm
moon run scripts/e2e.mbtx native
```

CI tests portable targets on Linux/macOS/Windows and executes native tests and
CLI on Linux/macOS. A configured CI job is not itself evidence that it passed.
Windows native runtime support is not claimed.

## Sources and roadmap

Apache-2.0; see [THIRD_PARTY.md](THIRD_PARTY.md). Independently written domain merge
layer, inspired by nbdime workflows; not a complete port or an originality claim.
moonrockz/notebooks supplies codecs, forey217/moonconfig generic JSON merging and
mizchi/bit_diff3 text merging. This project handles notebook cell/order/output
decisions. None of those implementations or tests have been copied.

Planned, not implemented: per-cell source-line merging, richer order reasoning,
browser review and editor integrations. No artificial commit-count target.
