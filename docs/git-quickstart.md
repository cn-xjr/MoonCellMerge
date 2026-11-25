# Use the prebuilt MoonCellMerge Git driver

Open [MoonCellMerge Actions](https://github.com/cn-xjr/MoonCellMerge/actions/workflows/ci.yml)
and select a successful run on `main`. Download the `mooncellmerge-driver`
artifact for your platform from the run's Artifacts section. GitHub requires
sign-in for artifact downloads, and the download expires after 30 days.
[GitHub artifact download instructions](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/download-workflow-artifacts)

Extract the ZIP. It includes the tested `mooncellmerge.wasm`, four demo
notebooks, the acceptance receipt, the tested MoonRun version and license
notices. Put `moonrun` from your MoonBit installation on PATH and check
`moonrun --version` against `moonrun-version.txt`. Running the driver requires
Git and MoonRun. The steps below use Bash (Git Bash on Windows).

## Set up a disposable repository

Set `TOOL` to the absolute path of the extracted directory. On Windows, use
forward slashes, for example `C:/Users/you/Downloads/MoonCellMerge driver`.
The demo sets configuration only in the new local repository.

```bash
TOOL='/absolute/path/to/extracted MoonCellMerge driver'
WORK=$(mktemp -d)
mkdir "$WORK/review" "$WORK/empty-hooks"
git init -b main "$WORK/notebooks"
cd "$WORK/notebooks"

git config --local user.name 'MoonCellMerge demo'
git config --local user.email 'demo@example.invalid'
git config --local commit.gpgsign false
git config --local core.hooksPath "$WORK/empty-hooks"
git config --local merge.cellmerge.name 'MoonCellMerge notebook merge'
git config --local merge.cellmerge.driver "moonrun '$TOOL/mooncellmerge.wasm' -- git-driver %O %A %B"
printf '* text eol=lf\n*.ipynb merge=cellmerge\n' > .gitattributes

cp "$TOOL/demo/base.ipynb" analysis.ipynb
git add -- .gitattributes analysis.ipynb
git commit -m 'Add baseline notebook'
git branch demo-base

git switch -c independent-edit
cp "$TOOL/demo/independent.ipynb" analysis.ipynb
git commit -am 'Edit a different cell'

git switch -c competing-edit demo-base
cp "$TOOL/demo/competing.ipynb" analysis.ipynb
git commit -am 'Edit the same cell'

git switch main
cp "$TOOL/demo/ours.ipynb" analysis.ipynb
git commit -am 'Edit the first cell'
git branch review-demo
```

## Merge and review

The first merge succeeds and `analysis.ipynb` contains both markers. The second
merge stops with a conflict and leaves the working copy on the current side.

```bash
git merge --no-edit independent-edit
grep -oE 'ours-marker|theirs-marker' analysis.ipynb

git switch review-demo
git merge --no-edit competing-edit
git status --short
```

Save the three versions from Git's index and generate the decision template.
In this example, `review` and `inspect` display unresolved conflicts and return 1.

```bash
git show :1:analysis.ipynb > "$WORK/review/base.ipynb"
git show :2:analysis.ipynb > "$WORK/review/ours.ipynb"
git show :3:analysis.ipynb > "$WORK/review/theirs.ipynb"
cd "$WORK/review"
moonrun "$TOOL/mooncellmerge.wasm" -- review base.ipynb ours.ipynb theirs.ipynb > review.json
moonrun "$TOOL/mooncellmerge.wasm" -- inspect review.json
moonrun "$TOOL/mooncellmerge.wasm" -- template review.json > decisions.json
```

Open `decisions.json` in a text editor. Keep its `review` field and replace
the empty `choices` with `{"/cells/2fcdfa53": "ours"}`. Then export, stage
and commit the reviewed notebook.

```bash
moonrun "$TOOL/mooncellmerge.wasm" -- resolve-to base.ipynb ours.ipynb theirs.ipynb decisions.json resolved.ipynb
cp resolved.ipynb "$WORK/notebooks/analysis.ipynb"
cd "$WORK/notebooks"
git add -- analysis.ipynb
git commit -m 'Merge reviewed notebook'
git status --short
```

For an existing repository, set the two local `merge.cellmerge` options and add
`*.ipynb merge=cellmerge` to its existing `.gitattributes`. Commit the attribute
rule as part of the repository setup so collaborators can configure the driver.
