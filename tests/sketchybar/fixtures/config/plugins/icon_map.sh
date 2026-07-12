#!/usr/bin/env bash

if [[ ${FAIL_ICON_APP:-} == "$1" ]]; then
  exit 1
fi

case "$1" in
  Safari) printf ':safari:\n' ;;
  Code) printf ':code:\n' ;;
  WezTerm) printf ':terminal:\n' ;;
  *) printf ':default:\n' ;;
esac
