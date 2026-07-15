#!/usr/bin/env bash

set -euo pipefail

if [[ ${SENDER:-} == mouse.clicked \
  && ${BUTTON:-} == left \
  && ${MODIFIER:-none} == none \
  && ${NAME:-} == space.* ]]; then
  aerospace workspace "${NAME#space.}"
fi
