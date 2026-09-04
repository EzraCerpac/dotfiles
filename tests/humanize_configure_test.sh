#!/usr/bin/env bash

set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
wizard="${root}/dot_local/share/humanize-text/configure.sh"
fixture=$(mktemp -d)
trap 'rm -rf "${fixture}"' EXIT

fake_home="${fixture}/home"
shadow_bin="${fixture}/shadow-bin"
proxy_state="${fixture}/proxy-started"
mkdir -p "${fake_home}/.local/bin" "${shadow_bin}"

cat >"${fake_home}/.local/bin/humanize-text" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  models)
    [[ -f "${HUMANIZE_TEST_PROXY_STATE}" ]] || exit 1
    printf '%s\n' gpt-test
    ;;
  save-model)
    mkdir -p "${HOME}/.config/humanize-text"
    printf '[llm]\nmodel = "%s"\n' "$2" >"${HOME}/.config/humanize-text/config.toml"
    ;;
  --text)
    exit 0
    ;;
  *)
    exit 2
    ;;
esac
SH
chmod +x "${fake_home}/.local/bin/humanize-text"

cat >"${shadow_bin}/humanize-text" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "upstream humanize-text shadowed the managed wrapper" >&2
exit 2
SH

cat >"${shadow_bin}/brew" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "services" && "${2:-}" == "list" ]]; then
  if [[ -f "${HUMANIZE_TEST_PROXY_STATE}" ]]; then
    printf '%s\n' "cliproxyapi started test"
  else
    printf '%s\n' "cliproxyapi none"
  fi
elif [[ "${1:-}" == "services" && "${2:-}" == "start" && "${3:-}" == "cliproxyapi" ]]; then
  touch "${HUMANIZE_TEST_PROXY_STATE}"
else
  exit 2
fi
SH

cat >"${shadow_bin}/security" <<'SH'
#!/usr/bin/env bash
if [[ " $* " == *" find-generic-password "* ]]; then
  exit 1
fi
exit 0
SH

cat >"${shadow_bin}/open" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "${shadow_bin}/humanize-text" "${shadow_bin}/brew" "${shadow_bin}/security" "${shadow_bin}/open"

output=$(
  printf '\ngpt-test\nfake-key\n' |
    env \
      HOME="${fake_home}" \
      USER="humanize-test" \
      PATH="${shadow_bin}:/usr/bin:/bin" \
      HUMANIZE_TEST_PROXY_STATE="${proxy_state}" \
      bash "${wizard}" 2>&1
)

[[ -f "${proxy_state}" ]]
grep -q 'model = "gpt-test"' "${fake_home}/.config/humanize-text/config.toml"
grep -q 'Setup complete' <<<"${output}"
if grep -q 'upstream humanize-text shadowed' <<<"${output}"; then
  printf '%s\n' "wizard used the PATH-shadowed upstream command" >&2
  exit 1
fi

printf '%s\n' "humanize configure tests passed"
