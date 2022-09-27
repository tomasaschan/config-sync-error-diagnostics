#!/bin/bash

set -Eueo pipefail

cache=./cache
mkdir -p $cache

rsyncs=$cache/rsyncs.json
if ! [[ -f $rsyncs ]]; then kubectl get rootsync,reposync -A -o json > $rsyncs; fi

<$rsyncs jq -f organize-errors.jq
