# Contributor guidance for Claude Code

## Python 3.14 support

This repo has an in-progress Python 3.14 support effort, documented in
[`README-3.14.md`](README-3.14.md). That file is the canonical running log of
the work and opens with "Keep this file up to date."

**When you make any 3.14-related change** (packaging, CI, test or docs
toolchain, or C/C++ extension build/link fixes), also update `README-3.14.md`:

- Add or extend the relevant entry under `## Changes`.
- Add a row to the `## Changelog` table at the bottom (use `_pending_` for the
  commit hash if the change isn't committed yet).
- Correct any now-stale statements in the file rather than leaving them.

**Also update `README-3.14.md` for backward-compatibility fixes to the model
load path** - i.e. any change that makes this version (Gensim 4) load models
saved by Gensim 3.x. These aren't 3.14-specific, but they are tracked in the
same file (see its section 7 for an example). Follow the same steps above, and
note in the entry that the change is not 3.14-specific.

## Building the extensions

Some Cython extensions are C++ (`doc2vec_inner`, `word2vec_corpusfile`,
`fasttext_corpusfile`, `doc2vec_corpusfile`). On Linux they are linked with
`-lstdc++` explicitly (`setup.py`, `make_cpp_ext`) because some interpreters
report `CXX=gcc`, which otherwise links without the C++ runtime and makes the
modules fail to import with `undefined symbol: __gxx_personality_v0`. See
section 5 of `README-3.14.md` for the full rationale.
