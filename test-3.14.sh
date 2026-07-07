#!/bin/bash
set -e

pip install -e '.[test]'
pip install flake8
flake8 --ignore E12,W503 --max-line-length 120 --show-source gensim
pip install -e '.[docs]'
make -C docs/src html
SKIP_NETWORK_TESTS=1 pytest -v gensim/test
