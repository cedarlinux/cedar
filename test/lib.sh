#!/usr/bin/env bash
# Assertion helpers for Cedar image tests. Sourced by test-image.sh.
# NOTE: every podman run needs --platform=linux/amd64; the base is multi-arch
# and an arm64 host silently selects the wrong image.

FAILURES=0
PLATFORM="${PLATFORM:-linux/amd64}"

pass() { printf '  \033[32mok\033[0m   %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

# check <description> <expected-substring> <command...>
check() {
  local desc=$1 expected=$2
  shift 2
  local actual rc
  actual=$(podman run --rm --platform="$PLATFORM" "$IMAGE" "$@" 2>&1); rc=$?
  if (( rc != 0 )); then
    fail "$desc (command exited $rc)"
    printf '       %s\n' "${actual:0:300}"
    return
  fi
  if [[ "$actual" == *"$expected"* ]]; then
    pass "$desc"
  else
    fail "$desc"
    printf '       expected to contain: %s\n' "$expected"
    printf '       got: %s\n' "${actual:0:400}"
  fi
}

# check_file_exists <description> <path>
check_file_exists() {
  local desc=$1 path=$2
  if podman run --rm --platform="$PLATFORM" "$IMAGE" test -e "$path" 2>/dev/null; then
    pass "$desc"
  else
    fail "$desc"
    printf '       missing: %s\n' "$path"
  fi
}

# summary MUST be the last line of the calling script — it sets the exit status.
summary() {
  echo
  if (( FAILURES == 0 )); then
    printf '\033[32mAll checks passed.\033[0m\n'
    return 0
  fi
  printf '\033[31m%d check(s) failed.\033[0m\n' "$FAILURES"
  return 1
}
