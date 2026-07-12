#!/usr/bin/env bash

set -euo pipefail

if [[ ${SENDER:-} == mouse.clicked \
  && ${BUTTON:-} == left \
  && -z ${MODIFIER:-} \
  && ${NAME:-} == space.* ]]; then
  aerospace workspace "${NAME#space.}"
fi
