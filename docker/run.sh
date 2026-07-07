#!/usr/bin/env bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR" || exit 1
. ./common.sh

parent=$(dirname "$DIR")

docker run -it \
    --platform=linux/amd64 \
    -v "$parent":/home/guser/src \
    gensim:"$GENSIM_VERSION" \
    bash
