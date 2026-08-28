# Python 3.14 support

This document summarizes the work done to make gensim build, test, and
document cleanly on Python 3.14, and the reasoning behind each change.

> Keep this file up to date. When you make a further 3.14-related change,
> add it under the relevant section and add a row to the changelog at the
> bottom.

## Supported Python versions

<https://devguide.python.org/versions/#supported-versions>

Supported: **3.11, 3.12, 3.13, 3.14**.

Python 3.9 and 3.10 support was dropped (both are at or near end of life).
`python_requires` is now `>=3.11`, the 3.9/3.10 classifiers were removed,
and the CI matrices (`tests.yml`, `build-wheels.yml`) build/test only
3.11-3.14. Dead 3.9/3.10-only code was removed too: the `POT` (`< 3.11`)
and `nmslib` (`< 3.10`) test-dependency install gates, the
`upgrade_pip_py310.py` multibuild helper, and the NmslibIndexer feature
(see below).

## Status

- Library builds from source on Python 3.14 (all Cython extensions compile).
- `import gensim` works.
- Test suite passes: `SKIP_NETWORK_TESTS=1 pytest gensim/test` gives
  0 failures (990 passed, ~125 skipped at time of writing).
- Documentation builds on Python 3.14 with a modern Sphinx toolchain.

Verified locally on macOS (arm64) with Python 3.14.6, NumPy 2.5.1,
SciPy 1.18.0, Cython 3.2.8, and on Linux (x86_64) with Python 3.14.6.

Note: macOS uses the `spawn` multiprocessing start method, so the
`WikiCorpus` / `segment_wiki` tests always took the serial `chunkize`
path there and passed. On Linux, 3.14 switched the default start method
to `forkserver`, which exposed the `chunkize` pickling bug fixed in
section 6.

## Key finding

The gensim library code needed **almost no changes** for Python 3.14.
The existing numpy-first `triu` fallback in `gensim/matutils.py` already
handles the SciPy >= 1.13 removal, and there is no removed-stdlib or
deprecated-NumPy-scalar usage in the source. The one source fix is in
`gensim/utils.py`: the background `chunkize` worker had to be gated on
the multiprocessing start method, because 3.14 changed the Linux default
from `fork` to `forkserver` (see section 6). Everything else below is
packaging, CI, test-dependency, and documentation-toolchain work.

## Changes

### 1. Declare and build wheels for 3.14

- `setup.py`: added the `Programming Language :: Python :: 3.14`
  classifier (`python_requires` is `>=3.11`).
- `.github/workflows/build-wheels.yml` and `tests.yml`:
  - Bumped `pypa/cibuildwheel` to v4.x (3.14 is a default build target
    there; the previous v3.1.4 predates stable-3.14-by-default).
  - Removed `cp314*` from `CIBW_SKIP` and `CIBW_TEST_SKIP`.
  - Both CI test matrices build/test 3.11-3.14 (macOS, Ubuntu, Windows).
  - On 3.14 the wheel test installs the newest NumPy instead of
    `oldest-supported-numpy` (which has no mapping for 3.14).
- `pyproject.toml`: refreshed the stale build-requires comment. pip's
  build isolation resolves a 3.14-compatible NumPy automatically, so no
  version change was needed.

Rationale: 3.14 was explicitly excluded from wheel builds and the CI
test matrix. The C/C++ extensions compile fine on 3.14 with a current
Cython, so the only work was the packaging/CI metadata. (Linking the
C++ extensions needed one small fix on some interpreters — see section 5.)

### 2. Test dependencies unavailable on 3.14

Several optional, native test/docs dependencies have no working build on
Python 3.14. They are now gated out on 3.14 (the same conditional-append
pattern that `POT` and `nmslib` used for older Pythons before those gates
were removed). The affected tests skip gracefully when the dependency is
absent.

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
  - Suppressed the benign `config.cache` warning triggered by the
    `sort_key` callable in `sphinx_gallery_conf`.
- Removed the now-unused vendored theme and the custom index template.
- `.github/workflows/build-docs.yml`: build docs on Python 3.14 (was
  pinned to 3.12).

Verified: `sphinx-build -W` (warnings-as-errors, as the Makefile uses)
completes cleanly on Python 3.14 with example execution disabled.

Later pin refreshes (not 3.14 blockers, just keeping the docs
environment current):

- `requirements_docs.txt`: `nltk` 3.9.4 -> 3.10.0. nltk is a docs-only
  dependency (the gallery examples use it for stopwords, tokenizing, and
  lemmatizing); nothing under `gensim/` imports it. 3.9.4 already
  supported 3.14, so this is a routine bump. 3.10.0 requires Python
  >= 3.10 (gensim requires >= 3.11) and adds `defusedxml` to nltk's own
  dependencies. The `nltk` entry in `setup.py`'s `docs_testenv` stays
  unpinned, matching the other non-Sphinx docs deps there.

  Verified: every nltk API the gallery uses still imports and behaves the
  same under 3.10.0 - `nltk.download`, `nltk.corpus.stopwords`,
  `nltk.tokenize.RegexpTokenizer` (and the top-level `nltk.RegexpTokenizer`
  alias used by `run_compare_lda.py`), `nltk.stem.wordnet.WordNetLemmatizer`,
  `nltk.stem.porter.PorterStemmer`.

### 4. Drop Python 3.9 / 3.10 and remove NmslibIndexer

3.9 and 3.10 are at or near end of life, so support was dropped
(supported set is now 3.11-3.14):

- `setup.py`: removed the 3.9/3.10 classifiers, set `python_requires`
  to `>=3.11`, and deleted the now-dead `POT` (`< 3.11`) and `nmslib`
  (`< 3.10`) test-dependency install gates.
- `pyproject.toml`: bumped the NumPy build-requires marker to
  `python_version>='3.11'`.
- `.github/workflows/tests.yml`, `build-wheels.yml`: dropped the
  3.9/3.10 matrix rows and added `cp39-*`/`cp310-*` to `CIBW_SKIP`;
  removed the Windows-Py3.10 NumPy work-around. The `tests.yml` docs
  smoke-build job moved off 3.9 (which cannot install Sphinx 9.x) to
  3.13.
- Removed `continuous_integration/upgrade_pip_py310.py` (a 3.10-only
  pip work-around) and its call in `config.sh`.
- **Removed the NmslibIndexer feature** (`gensim/similarities/nmslib.py`,
  its tests, the `similarities/nmslib` docs page and apiref entry). It
  only ever worked on Python 3.9 + NumPy 1.x, so dropping 3.9 made it
  unusable on every supported version. This is a breaking removal of the
  public `gensim.similarities.NmslibIndexer` API.

### 5. Link the C++ extensions against libstdc++ explicitly

Four of gensim's Cython extensions are C++ (`doc2vec_inner`,
`word2vec_corpusfile`, `fasttext_corpusfile`, `doc2vec_corpusfile`).
setuptools decides which compiler driver to link a C++ extension with
from the interpreter's `CXX` / `LDCXXSHARED` sysconfig values. The
python.org Linux 3.14 build reports `CXX=gcc` (not `g++`), so these
extensions were **linked with `gcc`**, which does not pull in the C++
runtime. The extensions compiled and installed without error, but at
**import** time failed with:

```
ImportError: .../fasttext_corpusfile.cpython-314-*.so: undefined symbol: __gxx_personality_v0
```

(`__gxx_personality_v0` is a libstdc++ symbol.) Because the modules
could not import, gensim fell back to its "compiled extensions
unavailable" path, and every `autodoc` directive for an affected module
raised a warning. The docs Makefile builds with `sphinx-build -W`
(warnings-as-errors), so the 27 resulting warnings failed the build:

```
build finished with problems, 27 warnings (with warnings treated as errors).
make: *** [Makefile:37: html] Error 1
```

This surfaced via the documentation build, but the root cause is a
mis-linked extension, not a docs problem — the same modules also fail to
import at runtime on such interpreters.

Fix (`setup.py`, `make_cpp_ext`): on Linux, add `-lstdc++` to the C++
extensions' `extra_link_args` so libstdc++ is linked in regardless of
what `CXX`/`LDCXXSHARED` the interpreter reports. Compile and link args
are now tracked separately (`-lstdc++` is a link-only flag). macOS is
unaffected (it links libc++ via the existing `-stdlib=libc++`).

Verified with a clean rebuild under the default environment
(`CXX=gcc`): the link line is now `gcc ... -lstdc++`, `ldd` shows
`libstdc++.so.6`, the extensions import, and `make -C docs/src html`
completes with zero warnings.

Note: the previous "all Cython extensions compile" / "compile fine"
notes above were accurate about *compilation* but missed this *link*
step; interpreters whose `CXX` is `g++` (e.g. the macOS toolchain this
was first verified on) linked libstdc++ automatically and did not hit it.

### 6. Gate the background `chunkize` worker on the `fork` start method

Python 3.14 changed the default multiprocessing start method on Linux
from `fork` to `forkserver`. `gensim.utils.chunkize` (when
`maxsize > 0`) prepares chunks in a background `InputQueue`
(`multiprocessing.Process`) subprocess. With `fork`, the child inherits
the parent's `corpus` object directly; with `forkserver` (and `spawn`),
the `Process` object — including its `corpus` attribute — is **pickled**
to be sent to the child. When `corpus` is a generator (as it is for
`WikiCorpus` / `segment_wiki`), that fails:

```
TypeError: cannot pickle 'generator' object
  when serializing dict item 'corpus'
  when serializing gensim.utils.InputQueue state
```

This broke 21 tests (`TestWikiCorpus`, `TestSegmentWiki`) on Linux 3.14.

The pre-existing guard already aliased `chunkize` to `chunkize_serial`
on the `spawn` platforms (Windows, macOS + py3.8+), but keyed off
`os.name` / `sys.platform` / version rather than the actual start
method, so it missed Linux + `forkserver`.

Fix (`gensim/utils.py`): key the guard on
`multiprocessing.get_start_method() != 'fork'` instead of hardcoding
platforms. This covers `spawn` **and** `forkserver` on every OS and
Python version, keeping the parallel fast path only where it actually
works (`fork`, i.e. Linux < 3.14). The fallback warning now reports the
detected start method. Verified: the 21 tests pass on Linux 3.14
(`forkserver`), and the fast path is unchanged where `fork` is the
default.

### 7. Load Doc2Vec models saved by Gensim 3.8.3

Not a 3.14-specific fix - this is a backward-compatibility bug in the
4.x model-load path that surfaced while extending the test suite. The
old-doc2vec load path had no active coverage (its tests were all
disabled as `obsolete_test_*`), so it had regressed and could not load
any pre-4.0.0 `Doc2Vec` model:

```
AttributeError: 'Doc2Vec' object has no attribute 'dv'. Did you mean: 'dm'?
```

Three chained root causes:

- **`docvecs` -> `dv` rename never happened** (`gensim/models/doc2vec.py`).
  3.8.3 stored the doc-vectors under `docvecs`; 4.0.0 renamed the
  attribute to `dv` and turned `docvecs` into a deprecated property. The
  recursive loader in `utils._load_specials` walks the pickled
  `__recursive_saveloads` list (which still contains `'docvecs'`) and
  calls `getattr(self, 'docvecs')` - but the `docvecs` **property** (a
  data descriptor) shadows the pickled `__dict__` entry and returns
  `self.dv`, which does not exist yet. `Doc2Vec` had no `_load_specials`
  override to handle the rename. Added one (mirroring
  `Word2Vec._load_specials`) that renames the pickled attribute and
  fixes the `__recursive_saveloads` list before the base class recurses.
- **`_upconvert_old_d2vkv` used the raising `vocab` setter**
  (`gensim/models/keyedvectors.py`). `self.vocab = self.doctags` triggers
  the `vocab` setter, which raises since 4.0.0. Changed to write
  `self.__dict__['vocab']` directly, which is what `_upconvert_old_vocab()`
  pops back out.
- **Missing `expandos` / unconditional `del expandos['offset']`**
  (`gensim/models/keyedvectors.py`). `_upconvert_old_vocab()` needs
  `self.expandos`, but it is only initialised *after* the
  `_upconvert_old_d2vkv` call in the normal flow; and `'offset'` is only
  set for string doctags, so integer-tag-only models (empty `doctags`)
  hit a `KeyError`. Now `expandos` is ensured first and the offset
  remapping is guarded on `'offset' in self.expandos`.

Test (`gensim/test/test_doc2vec.py`): `test_load_3_8_3` loads a real
3.8.3 model (`d2v_lee_3.8.3.mdl`), asserts the up-converted shapes, and
round-trips it through save/load with inference + similarity search. Its
assertions were leftovers copied from an old tiny-model test and were
corrected to the actual lee-corpus values (`wv (3955, 100)`,
`dv (300, 100)`, `len(dv) == 300`, `corpus_total_words == 58152`).

Verified: `test_load_3_8_3` passes, and the full `test_doc2vec`,
`test_word2vec`, and `test_keyedvectors` suites pass (the keyedvectors
change is on the load path shared with word2vec).

Note: the `expandos` / `offset`-vecattr remapping described in the third
bullet was later superseded by section 8 - it never actually worked for
string doctags, and `_upconvert_old_d2vkv` no longer calls
`_upconvert_old_vocab` at all.

### 8. Load Doc2Vec models with string document tags

Also not a 3.14-specific fix - a second backward-compatibility bug on the
same load path, reported when loading a real 3.8.3 model with string
document tags:

```
AttributeError: 'gensim.models.doc2vec.Doctag' object has no attribute 'index'
```

The `d2v_lee_3.8.3.mdl` fixture added in section 7 uses integer tags, so
its `doctags` dict is empty and the string-doctag branch of
`_upconvert_old_d2vkv` was never exercised. A model with string tags
takes that branch and crashes.

Root cause: in Gensim <4.0.0 `Doctag` was a `namedtuple` whose fields
(`offset`, `word_count`, `doc_count`) live in the tuple itself. Gensim
4.0.0 redefined `Doctag` as a plain `__slots__` class that is **not** a
tuple subclass. Unpickling a pre-4.0.0 model reconstructs each `Doctag`
via `Doctag.__new__(Doctag, offset, word_count, doc_count)`, but the new
class ignores those positional args, so **every per-doctag attribute is
silently dropped** - the loaded `Doctag` objects are empty. The generic
`_upconvert_old_vocab()` path then reads `old_v.index` (and, in the
follow-up, a per-tag `offset` vecattr) off those empty objects and
raises.

Fix (`gensim/models/keyedvectors.py`): rewrite `_upconvert_old_d2vkv` to
rebuild `index_to_key` / `key_to_index` directly from the surviving
`offset2doctag` list and `max_rawint`, without touching the dead `Doctag`
objects or calling `_upconvert_old_vocab`. This is the exact array layout
Gensim 3.x used - integer "raw int" tags occupy rows `0..max_rawint`,
followed by the string tags in `offset2doctag` order - so the
reconstructed vectors are bit-identical to the originals. The per-tag
`word_count` / `doc_count` extras are unrecoverable (they were dropped on
unpickle) and are not needed for lookup, inference, or similarity search.
This also simplifies the integer-tag path, which produced the same result
by a longer route.

Test (`gensim/test/test_doc2vec.py`): `test_load_3_8_3_string_tags` loads
a real 3.8.3 string-tagged model (`d2v_string_tags_3.8.3.mdl`, built from
`common_texts`), asserts the reconstructed `index_to_key` /
`key_to_index`, verifies string-tag lookup, and round-trips through
save/load with inference + similarity search.

Verified: `test_load_3_8_3_string_tags`, `test_load_3_8_3`, the full
`test_doc2vec` and `test_keyedvectors` suites pass, and the reconstructed
doc-vectors are `array_equal` to the ones read by Gensim 3.8.3 itself.

### 9. Remove the bogus `except -1` on the `sdot` / `dsdot` typedefs

Not a 3.14-specific fix either - a leftover from the Cython 3 `noexcept`
migration (commit `6e1753a4`, which converted the rest of
`word2vec_inner.pxd` but missed these two lines).

The BLAS function-pointer typedefs for `sdot` and `dsdot` in
`gensim/models/word2vec_inner.pxd` were declared `except -1 nogil`.
Without the `?`, that tells Cython a return value of exactly -1 *always*
means an exception was raised, so no `PyErr_Occurred()` guard is emitted
and the value alone is taken as the error signal. For a dot product, -1.0
is an ordinary result.

The generated C for `our_dot_double` (`word2vec_inner.pyx:48`) was:

```c
__pyx_t_1 = dsdot(N, X, incX, Y, incY);
if (unlikely(__pyx_t_1 == ((double)-1.0))) __PYX_ERR(0, 48, __pyx_L1_error)
...
__pyx_L1_error:;
  __pyx_gilstate_save = __Pyx_PyGILState_Ensure();
  __Pyx_WriteUnraisable("gensim.models.word2vec_inner.our_dot_double", ...);
  __pyx_r = 0;
  __Pyx_PyGILState_Release(__pyx_gilstate_save);
```

So a dot product of exactly -1.0 inside the `nogil` training loop would
acquire the GIL and return **0.0 instead of -1.0**, with no exception
ever raised (`PyErr_WriteUnraisable` with nothing set is silent).
`our_dot_float` (`word2vec_inner.pyx:52`) generated the same code. Both
are on the hot path for every skip-gram / CBOW training step when SciPy's
BLAS is available, which is the normal case. Exactly -1.0f is rare with
real weights, so this was a latent silent-wrong-value path rather than a
visible failure.

The third call site, `init()` at `word2vec_inner.pyx:943`, was harmless:
it dots `10.0` with `0.01` to detect whether `sdot` returns float or
double, so it cannot hit the sentinel.

Fix: declare both typedefs `noexcept nogil`, matching every other
declaration in the file. The calls then compile to a plain cast with no
branch, no temporary, and no error label. No other `except -1` remains in
the Cython sources; the surviving `except *` and `except +` clauses in
`word2vec_corpusfile` are legitimate.

Verified by cythonizing `word2vec_inner.pyx` both ways with Cython 3.3.0
and diffing the generated C: no warnings either way, the error label and
`WriteUnraisableException` helper disappear, and the two `dsdot`/`sdot`
call sites become direct calls.

Note that the extensions must be rebuilt for this to take effect
(`python setup.py build_ext --inplace`), including `doc2vec_inner`,
`fasttext_inner` and the `*_corpusfile` modules, which cimport this
`.pxd`. Their own generated code is unchanged - they call `our_dot`,
which was already `noexcept`.

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
- **NmslibIndexer was removed** (it only worked on Python 3.9, now
  dropped). **POT** is not installed on any supported version, so the
  WMD/optimal-transport tests skip.
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

## Docker

In the `docker/` directory:

- build.sh: builds a docker image
- run.sh: runs the image with a bash shell

Once it's running, run `./test-3.14.sh`. This runs all the commands listed in CONTRIBUTING.md.

## Changelog

| Commit     | Summary                                                  |
|------------|----------------------------------------------------------|
| `8a3654a1` | build: support Python 3.14 (classifier, cibuildwheel, CI matrix) |
| `0d5b2d0b` | build: skip visdom test dep on Python 3.14               |
| `0f1fd9e3` | docs: build on Python 3.14 with a modern Sphinx toolchain |
| `d50df085` | build: exclude annoy on Python 3.14                      |
| `7af96b36` | build: drop Python 3.9/3.10 support (remove NmslibIndexer) |
| `9dd29720` | build: link C++ extensions against libstdc++ explicitly (fix `__gxx_personality_v0` import failure / docs build) |
| `ffb3cd77` | fix: gate background `chunkize` worker on the `fork` start method (fix `cannot pickle 'generator'` on Linux py3.14 `forkserver`) |
| `0978ee04` | fix: load Doc2Vec models saved by Gensim 3.8.3 (rename `docvecs` -> `dv`, repair `_upconvert_old_d2vkv`) |
| `8ec1479c` | fix: load Doc2Vec models with string document tags saved by Gensim 3.8.3 (rebuild `_upconvert_old_d2vkv` from `offset2doctag`/`max_rawint`) |
| `_pending_` | build: bump the docs-only `nltk` pin to 3.10.0                |
| `_pending_` | fix: drop the bogus `except -1` on the `sdot`/`dsdot` typedefs (a -1.0 dot product silently returned 0.0 and grabbed the GIL) |

Add new rows here as further 3.14 changes land.
