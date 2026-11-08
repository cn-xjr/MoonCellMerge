# MoonCellMerge

Conservative cell-ID-aware three-way Jupyter notebook merge and review in MoonBit.
For teams maintaining notebooks in Git and developers building notebook tools.

## Implemented scope

Source version 0.1.0; not published to Mooncakes. Supports nbformat 4.5 with
unique legal cell IDs; code, Markdown and raw cells.
Notebook-level metadata also merges independent top-level producer keys. Nested
values such as kernelspec or language_info remain atomic; competing nested edits
require `/notebook/metadata` review. Deletion differs from a present JSON null.
Saved reviews are recomputed on restoration: regenerate an older review if the
new analysis changes its conflict list rather than applying obsolete choices.

Independent cell edits merge. Different
execution-evidence edits conflict atomically; bounded source composition is
described below. Independent cell fields
and top-level metadata keys can merge within the same cell. Source, cell type,
outputs and execution_count are one atomic group, preventing accidental mixing
of one branch's code with the other branch's execution evidence. Nested metadata
and attachments remain atomic values; competing edits require whole-cell review.
Single-sided insert/delete/move works;
simultaneous deletions and insertions into different surviving-base gaps also
compose when both branches preserve surviving base order. Different insertions
into the same gap remain explicit order conflicts; matching insertion blocks
are retained once. Moves, competing anchors and delete/edit cases are not guessed.
Incompatible orders require an explicit complete retained-ID array. Delete/edit
conflicts retain evidence. Changed source with nonempty outputs requires explicit
whole-cell acknowledgment. Outputs are never silently cleared or certified current.

Unknown JSON fields, metadata, attachments and output payloads are retained as
opaque values. Numbers retain exact JSON spellings, including integers beyond
2^53. Duplicate keys fail. Object keys sort deterministically; whitespace and
original key order are not retained. Reader validation covers the structural
subset needed by merging, not the entire nbformat JSON Schema. No kernel runs.

Limits: 4 million UTF-16 units per notebook, 1 million combined merge input units,
10,000 cells, JSON depth 64. Unsupported format versions/types and invalid IDs
are rejected.
Structural numeric fields (`nbformat`, `nbformat_minor`, non-null
`execution_count`) require plain nonnegative decimal integer tokens through
2147483647. Fractions, exponents and negative zero are rejected before floating
point rounding; producer metadata retains arbitrary original numeric spellings.

No legacy ID guessing, notebook trust signatures, DIB conversion,
general source-line merging or proof of execution-result freshness is implemented.

Bounded source composition is available for unchanged cell kinds with no stored
outputs or execution counts. Each branch is represented as one contiguous edit
between its common prefix/suffix lines; disjoint edits merge, including adjacent
line replacements. Overlaps, competing insertions, insertion-boundary ambiguity,
and sources above 100,000 UTF-16 units or 4,000 lines remain whole-cell conflicts.
CRLF, LF and missing final newlines are retained. This is conservative composition,
not a language-aware merge or a claim of arbitrary multi-hunk support.

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

Inspect saved conflicts with `moon run cmd/main -- inspect REVIEW.json` (exit 1
when conflicts remain). The public `Review::details` and `Review::to_text` expose
all three snapshots, conflict kinds and actionable selection guidance. Missing
values differ from JSON null. Snapshots are caller-owned; changing them cannot
change the review. Text escapes control characters rather than rendering them.

`review` prints an envelope with version, all three exact input texts and conflict
paths. Save stdout. Exit codes: 0 clean, 1 conflicts, 2 invalid input/I/O.
Root-field conflicts use `/notebook/<escaped-key>`, cell conflicts use
`/cells/<id>`, and order uses `/cell-order`; extension keys cannot collide with
the reserved cell/order namespace. Keys use JSON Pointer escaping.

Build a decision JSON object containing `review` (the entire saved envelope), `choices`
(each conflict path mapped to `base`, `ours` or `theirs`), and, for `/cell-order`,
an `order` array listing every retained ID exactly once. Clean reviews use empty
choices. Missing, duplicate, unknown or stale decisions fail.

Generate the complete input-bound skeleton without hand-copying JSON:
`moon run cmd/main -- template REVIEW.json`. Fill its initially empty `choices`
object and optional `order`. The library exposes `Review::decision_template`
and `Review::apply_decisions`; CLI and downstream consumers use the same strict
validation and exact-input binding. An empty template never accepts conflicts.

```text
moon run cmd/main -- resolve BASE.ipynb OURS.ipynb THEIRS.ipynb DECISIONS.json
```

Resolved JSON goes to stdout. Do not redirect onto an input file. Review/resolve
do not write destinations. Whole-cell selection acknowledges all its values,
including potentially stale output; it does not establish scientific correctness.

For a destination file, use exclusive creation instead of shell redirection:

```text
moon run cmd/main -- merge-to BASE.ipynb OURS.ipynb THEIRS.ipynb NEW.ipynb
moon run cmd/main -- resolve-to BASE.ipynb OURS.ipynb THEIRS.ipynb DECISIONS.json NEW.ipynb
```

Both commands finish analysis/decision validation before opening the output.
Existing destinations (including an input file) fail with exit 2 and are never
truncated. A conflicting `merge-to` exits 1 without creating the destination;
stale/invalid decisions also create no destination. Creation uses the filesystem's
exclusive-create operation, not a check-then-write race. A storage failure during
writing can leave a partial newly created file; inspect and remove it explicitly
before retrying. This is not a claim of crash-atomic publication or directory
durability. The Git driver's overwrite behavior is documented separately below.

## Git driver

Configure the consuming repository locally (replace the absolute checkout path):

```text
moon build --target wasm cmd/main
git config merge.cellmerge.name "MoonCellMerge notebook merge"
git config merge.cellmerge.driver 'moonrun "/absolute/path/MoonCellMerge/_build/wasm/debug/build/cmd/main/main.wasm" -- git-driver %O %A %B'
```

Add `*.ipynb merge=cellmerge` to its .gitattributes. Quote paths containing spaces.
Only a clean merge writes Git's temporary OURS file; conflicts leave it unchanged
and exit 1. Use review/resolve to resolve conflicts, then stage the reviewed file.
The initial driver uses a normal file write, not a durable atomic rename; use
Git's original versions to recover from an interrupted write.

Run `moon run scripts/git_e2e.mbtx` to exercise actual Git merges in isolated
repositories, with a copied Wasm executable and filenames containing spaces.
It verifies clean auto-merge, unchanged OURS on conflict, all three index stages,
merge abort/retry, template-based resolution and the final Git merge commit.
Temporary repositories have synthetic fixture-only authors and no remotes;
your repository configuration/history is not modified. `CELLMERGE_MOONRUN` may
select a particular moonrun executable. Artifacts are retained for inspection.

## Library and adoption

Import `cn-xjr/mooncellmerge` in moon.pkg; until publication use a local moon.work
containing this checkout and your separate module. API: `read_notebook`, `merge`,
`Review::conflicts`, `Review::to_json`, `restore_review`, `Review::resolve`,
`Choice`, `MergeError`, `canonical`. Notebook/Review internals are private.
See pkg.generated.mbti. Returned conflict arrays are copies.

Verify the actual source ZIP from a separate consuming module:

```text
moon run scripts/consumer.mbtx wasm
moon run scripts/consumer.mbtx wasm-gc
moon run scripts/consumer.mbtx js
moon run scripts/consumer.mbtx native
```

The script checks the package allowlist/licenses, extracts the ZIP into a fresh
directory and creates a workspace with only that extracted library and the
separate consumer. The original checkout cannot satisfy its dependency. Two
public-API tests and a real executable run per target. Git and Windows tar or
POSIX unzip are required; native requires a C compiler. Temporary files remain
for inspection. This is local package verification, not Mooncakes publication.

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

Planned, not implemented: arbitrary multi-hunk source merging, simultaneous move reasoning,
browser review and editor integrations. No artificial commit-count target.
