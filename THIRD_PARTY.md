# Sources and licenses

- fixtures/upstream.ipynb: unmodified tests/test4.5.ipynb from
  https://github.com/jupyter/nbformat/tree/cfb73afdd2a7f358953f2a34f747fd0d0e9d6288
  retrieved 2026-11-07; BSD-3-Clause, notice in fixtures/JUPYTER_LICENSE.
  E2E changes temporary copies of cell source, not this original fixture.
- https://nbformat.readthedocs.io/en/latest/format_description.html is the format
  reference. No documentation prose copied.
- https://github.com/jupyter/nbdime (BSD-3-Clause): workflow reference, no code or
  tests copied and no claim of identical merge policy.
- moonbitlang/async@0.22.5 (Apache-2.0): CLI file/process I/O. MoonBit core handles
  JSON parsing with duplicate rejection and exact number representation.
- Root LICENSE is the standard Apache-2.0 license text. Tests were written for
  this project. No external diff executable or Python runtime dependency.
