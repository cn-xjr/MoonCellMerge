# Sources and licenses

- fixtures/upstream.ipynb: unmodified tests/test4.5.ipynb from
  https://github.com/jupyter/nbformat/tree/cfb73afdd2a7f358953f2a34f747fd0d0e9d6288
  retrieved 2026-11-07; BSD-3-Clause, notice in fixtures/JUPYTER_LICENSE.
  The driver bundle includes this fixture and three source-edited demo copies,
  with the BSD-3-Clause notice distributed as JUPYTER_LICENSE.
- fixtures/workflows/: project-authored Apache-2.0 notebook snapshots and
  inline SVG assets. The report and workshop histories use illustrative data.
  Expected notebooks are authored alongside the inputs, independently of the
  merge implementation.
- fixtures/corpus/awkward-arrays.ipynb is the original Awkward Array
  tutorial, BSD-3-Clause. Git blob `5c53e00ace9d5f4f6193245cbaa9c1f89cdad096`.
  The notice is in `fixtures/corpus/AWKWARD_LICENSE`.
  [Upstream at 2b1e4ec](https://github.com/scikit-hep/awkward/blob/2b1e4ec35d3325ecd2b707b2d67bb57fe082871f/docs/getting-started/jagged-ragged-awkward-arrays.ipynb)
- fixtures/corpus/jupyterlab-long-output.ipynb and jupyterlab-legacy-mime.ipynb
  are original JupyterLab regression notebooks under BSD-3-Clause. Their Git
  blobs are `c01d0f57f6cbcd3acf78488d3d0b6188c45adde3` and
  `57b2ed6a7dbda33579af70bddea07d4d1b482cb1`. The notice is in
  `fixtures/corpus/JUPYTERLAB_LICENSE`.
  [Long output at 585894c](https://github.com/jupyterlab/jupyterlab/blob/585894cf7b1a5a226d579bcd94c9e759df5ceb86/galata/test/jupyterlab/notebooks/long_output_and_headings.ipynb)
  [Legacy MIME at 585894c](https://github.com/jupyterlab/jupyterlab/blob/585894cf7b1a5a226d579bcd94c9e759df5ceb86/galata/test/galata/notebooks/simple_test.ipynb)
- nbformat 5.11.1, BSD-3-Clause, independently validates exported JSON in
  corpus acceptance. It is installed separately from PyPI for that check.
  [Jupyter validator release](https://pypi.org/project/nbformat/5.11.1/)
- https://nbformat.readthedocs.io/en/latest/format_description.html is the format
  reference. No documentation prose copied.
- https://github.com/jupyter/nbdime (BSD-3-Clause): workflow reference, no code or
  tests copied and no claim of identical merge policy.
- moonbitlang/async@0.22.5 (Apache-2.0): CLI file/process I/O. MoonBit core handles
  JSON parsing with duplicate rejection and exact number representation.
- moonbitlang/x@0.5.5 (Apache-2.0): SHA-256 and hexadecimal rendering for
  compact review bindings, plus platform-aware path handling and hexadecimal
  temporary names for file publication. Source at https://github.com/moonbitlang/x.
- scripts/large_review_e2e.mbtx expands the project-authored report SVG at runtime
  with an XML comment and preserves the existing rich MIME output from the fixture.
- Root LICENSE is the standard Apache-2.0 license text. Tests were written for
  this project. No external diff executable or Python runtime dependency.
