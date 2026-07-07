#!/usr/bin/env bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR" || exit 1
. ./common.sh

docker build -f Dockerfile \
  --platform=linux/amd64 \
  --tag gensim:$GENSIM_VERSION \
  ..
