# Python 3.14 support

This document summarizes the work done to make gensim build, test, and
document cleanly on Python 3.14, and the reasoning behind each change.

> Keep this file up to date. When you make a further 3.14-related change,
> add it under the relevant section and add a row to the changelog at the
> bottom.

## Status

- Library builds from source on Python 3.14 (all Cython extensions compile).
- `import gensim` works.
- Test suite passes: `SKIP_NETWORK_TESTS=1 pytest gensim/test` gives
  0 failures (990 passed, ~125 skipped at time of writing).
- Documentation builds on Python 3.14 with a modern Sphinx toolchain.

Verified locally on macOS (arm64) with Python 3.14.6, NumPy 2.5.1,
SciPy 1.18.0, Cython 3.2.8.

## Key finding

The gensim library code needed **no changes** for Python 3.14. The
existing numpy-first `triu` fallback in `gensim/matutils.py` already
handles the SciPy >= 1.13 removal, and there is no removed-stdlib or
deprecated-NumPy-scalar usage in the source. Everything below is
packaging, CI, test-dependency, and documentation-toolchain work.

## Changes

### 1. Declare and build wheels for 3.14

- `setup.py`: added the `Programming Language :: Python :: 3.14`
  classifier. `python_requires='>=3.9'` already covers 3.14.
- `.github/workflows/build-wheels.yml`:
  - Bumped `pypa/cibuildwheel` to v4.x (3.14 is a default build target
    there; the previous v3.1.4 predates stable-3.14-by-default).
  - Removed `cp314*` from `CIBW_SKIP` and `CIBW_TEST_SKIP`.
  - Added `3.14` rows to the test matrix (macOS, Ubuntu, Windows).
  - On 3.14 the wheel test installs the newest NumPy instead of
    `oldest-supported-numpy` (which has no mapping for 3.14), reusing
    the pattern already in place for Windows + Py3.10.
- `pyproject.toml`: refreshed the stale build-requires comment. pip's
  build isolation resolves a 3.14-compatible NumPy automatically, so no
  version change was needed.

Rationale: 3.14 was explicitly excluded from wheel builds and the CI
test matrix. The C/C++ extensions compile fine on 3.14 with a current
Cython, so the only work was the packaging/CI metadata.

### 2. Test dependencies unavailable on 3.14

Several optional, native test/docs dependencies have no working build on
Python 3.14. They are now gated out on 3.14, matching the pre-existing
pattern for `nmslib` (`< 3.10`) and `POT` (`< 3.11`). The affected tests
skip gracefully when the dependency is absent.

- **visdom** (`setup.py`): unmaintained (last release 0.2.4, 2022); its
  `setup.py` imports the removed `pkg_resources` module, so
  `pip install -e .[test]` failed at build time. Gated out on 3.14. The
  visdom callback test skips when visdom is absent.
- **annoy** (`setup.py`, `requirements_docs.txt`): no wheels for recent
  Python, and the source build is broken on 3.14 - nearest-neighbour
  queries return incorrect results (a vector is not even its own nearest
  neighbour). spotify/annoy is unmaintained (last release 1.17.3, 2023).
  Gated out on 3.14. The `AnnoyIndexer` tests skip when annoy is absent.

### 3. Documentation toolchain

The pinned docs toolchain could not build on 3.14, so it was migrated to
a current one. See the commit `docs: build on Python 3.14 ...` for full
detail.

Blockers found:

- `Sphinx==5.1.1` cannot import on Python 3.13+ - its epub builder
  imports the stdlib `imghdr` module, removed in 3.13.
- The vendored custom theme under `docs/src/sphinx_rtd_theme/` (gensim's
  branded landing-page theme, not the standard RTD theme) relied on
  template variables removed in Sphinx 7.0 (`style`, `script_files`,
  mutable `css_files`). No Sphinx version both runs on 3.14 and supports
  that old template API, so the theme had to change.

Changes made (decision: adopt the standard, maintained theme):

- `setup.py` / `requirements_docs.txt`: bumped `Sphinx` (9.1.0),
  `sphinx-gallery` (0.21.0), `sphinxcontrib.programoutput` (0.20); added
  the maintained `sphinx-rtd-theme` (3.1.0); dropped the unused
  standalone `sphinxcontrib-napoleon` (the built-in `sphinx.ext.napoleon`
  is used instead).
- `docs/src/conf.py`:
  - Use the installed `sphinx-rtd-theme` package instead of the vendored
    copy (`html_theme_path = []`).
  - Replaced the custom marketing landing page (`indexcontent.html` +
    `master_doc = 'indextoc'`) with a standard `index.rst` root doc.
  - Ported `sort_key` to the new sphinx-gallery `within_subsection_order`
    key-function API (the old factory signature broke).
  - `autodoc_mock_imports = ['nmslib']` so autodoc can document
    `gensim.similarities.nmslib` without importing the (unavailable)
    package.
  - Suppressed the benign `config.cache` warning triggered by the
    `sort_key` callable in `sphinx_gallery_conf`.
- Removed the now-unused vendored theme and the custom index template.
- `.github/workflows/build-docs.yml`: build docs on Python 3.14 (was
  pinned to 3.12).

Verified: `sphinx-build -W` (warnings-as-errors, as the Makefile uses)
completes cleanly on Python 3.14 with example execution disabled.

## Building and testing on 3.14

```bash
# build the extensions in place
python setup.py build_ext --inplace

# install with test dependencies
pip install -e .[test]

# run the tests (skip network tests, see limitations below)
SKIP_NETWORK_TESTS=1 pytest -v gensim/test

# build the docs
pip install -e .[docs]
make -C docs/src html
```

## Known limitations on 3.14

- **annoy is unavailable.** The `AnnoyIndexer` feature and its tests are
  skipped. The `run_annoy.py` documentation gallery example cannot
  execute on 3.14; full gallery execution would need that example
  excluded on 3.14 (not yet done).
- **nmslib and POT** remain unavailable (pre-existing; no 3.14 wheels).
  Their tests skip.
- **Network tests** (`gensim/test/test_api.py`) require downloading code
  from the external gensim-data repository, which uses an old
  `smart_open` API removed in smart_open 2.0+. These fail on any Python
  version, not just 3.14, and are not fixable in this repository. Skip
  them with `SKIP_NETWORK_TESTS=1`.
- **`test_cbow_hs_online`** is a pre-existing flaky (non-deterministic,
  multi-worker) training-convergence test. It passes in isolation and is
  unrelated to 3.14; left as-is for now.
- **Free-threaded 3.14t** is out of scope - it needs separate GIL-safety
  work on the C extensions. Only the standard build is supported.
- **Docs appearance changed** - local docs now use the stock
  Read-the-Docs theme rather than the old branded landing page.

## Changelog

| Commit     | Summary                                                  |
|------------|----------------------------------------------------------|
| `8a3654a1` | build: support Python 3.14 (classifier, cibuildwheel, CI matrix) |
| `0d5b2d0b` | build: skip visdom test dep on Python 3.14               |
| `0f1fd9e3` | docs: build on Python 3.14 with a modern Sphinx toolchain |
| `d50df085` | build: exclude annoy on Python 3.14                      |

Add new rows here as further 3.14 changes land.
