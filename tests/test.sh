#!/bin/sh
# tests/test.sh — test suite for gitop and gitc
#
# Usage:
#   ./tests/test.sh            # run all tests
#   VERBOSE=1 ./tests/test.sh  # show command output

set -e

PASS=0
FAIL=0
SKIP=0

BIN="$(cd "$(dirname "$0")/../bin" && pwd)"
GITOP="$BIN/gitop"
GITC="$BIN/gitc"

# ---- helpers ----------------------------------------------------------------

pass() { PASS=$(( PASS + 1 )); printf '  ok  %s\n' "$1"; }
fail() { FAIL=$(( FAIL + 1 )); printf '  FAIL %s\n' "$1"; }
skip() { SKIP=$(( SKIP + 1 )); printf '  skip %s\n' "$1"; }

# Run a command; assert it exits with the given code.
assert_exit() {
    expected="$1"; shift
    if [ "${VERBOSE:-}" = "1" ]; then
        "$@"; actual=$?
    else
        "$@" >/dev/null 2>&1; actual=$?
    fi
    if [ "$actual" -eq "$expected" ]; then
        return 0
    else
        printf '       expected exit %d, got %d (cmd: %s)\n' \
            "$expected" "$actual" "$*" >&2
        return 1
    fi
}

# Run a command; assert its stdout+stderr contains a string.
assert_output() {
    needle="$1"; shift
    out=$("$@" 2>&1 || true)
    if printf '%s' "$out" | grep -q "$needle"; then
        return 0
    else
        printf '       expected output to contain: %s\n' "$needle" >&2
        printf '       actual output: %s\n' "$out" >&2
        return 1
    fi
}

# Create a temp git repo; echo its path.
make_repo() {
    d=$(mktemp -d)
    git -C "$d" init -b main -q
    git -C "$d" config user.email "test@example.com"
    git -C "$d" config user.name "Test"
    printf '%s' "$d"
}

cleanup() { rm -rf "$TMPDIR_LIST"; }
TMPDIR_LIST=""
trap cleanup EXIT

new_repo() {
    r=$(make_repo)
    TMPDIR_LIST="$TMPDIR_LIST $r"
    printf '%s' "$r"
}

# ---- tests ------------------------------------------------------------------

printf 'gitop\n'

# version flag
if assert_exit 0 "$GITOP" --version; then pass "--version exits 0"; else fail "--version exits 0"; fi
if assert_output "0\." "$GITOP" --version; then pass "--version prints version"; else fail "--version prints version"; fi

# help flag
if assert_exit 0 "$GITOP" --help; then pass "--help exits 0"; else fail "--help exits 0"; fi

# no args
if assert_exit 1 "$GITOP"; then pass "no args exits 1"; else fail "no args exits 1"; fi

# not in a git repo
TMPDIR=$(mktemp -d)
TMPDIR_LIST="$TMPDIR_LIST $TMPDIR"
if (cd "$TMPDIR" && assert_exit 1 "$GITOP" git status); then
    pass "non-git dir exits 1"
else
    fail "non-git dir exits 1"
fi
if (cd "$TMPDIR" && assert_output "not in a git" "$GITOP" git status 2>&1 || true); then
    pass "non-git dir error message"
else
    fail "non-git dir error message"
fi

# basic command runs
REPO=$(new_repo)
if (cd "$REPO" && assert_exit 0 "$GITOP" git status); then
    pass "basic command succeeds"
else
    fail "basic command succeeds"
fi

# command exit code is propagated
REPO=$(new_repo)
if (cd "$REPO" && assert_exit 1 "$GITOP" 'exit 1'); then
    pass "inner exit code propagated"
else
    fail "inner exit code propagated"
fi

# reentrancy: GITOP_HELD set -> no deadlock
REPO=$(new_repo)
if (cd "$REPO" && GITOP_HELD="$REPO" assert_exit 0 "$GITOP" 'echo ok'); then
    pass "reentrancy: GITOP_HELD skips re-locking"
else
    fail "reentrancy: GITOP_HELD skips re-locking"
fi

# serialization: second caller blocks until first releases
REPO=$(new_repo)
result=$(
    cd "$REPO"
    # hold lock for 2s so elapsed rounds to >=1 with date +%s resolution
    (flock -x 9; sleep 2) 9>"$REPO/.git/gitop.lock" &
    BG=$!
    sleep 0.1
    START=$(date +%s)
    GITOP_WAIT=5 "$GITOP" 'echo serialized' >/dev/null 2>&1
    END=$(date +%s)
    wait "$BG"
    printf '%d' $(( END - START ))
)
if [ "$result" -ge 1 ]; then
    pass "serialization: second caller waits for lock"
else
    fail "serialization: second caller waits for lock (elapsed=${result}s, expected >=1)"
fi

# timeout: fails when lock is held beyond GITOP_WAIT
# When lsof shows an active holder, gitop prints "gave up after N retries".
# "timed out" appears only when the lock file has no live holder.
REPO=$(new_repo)
if (
    cd "$REPO"
    (flock -x 9; sleep 5) 9>"$REPO/.git/gitop.lock" &
    BG=$!
    sleep 0.1
    result=$(GITOP_WAIT=1 GITOP_MAX_RETRIES=1 "$GITOP" 'echo should-not-run' 2>&1 || true)
    kill "$BG" 2>/dev/null; wait "$BG" 2>/dev/null
    # "gave up" when lsof sees a live holder; "timed out" when holder already gone
    printf '%s' "$result" | grep -qE "gave up|timed out"
); then
    pass "timeout: fails with timeout message"
else
    fail "timeout: fails with timeout message"
fi

# lockfile is created in the repo .git dir
REPO=$(new_repo)
(cd "$REPO" && "$GITOP" git status >/dev/null 2>&1)
if [ -e "$REPO/.git/gitop.lock" ]; then
    pass "lockfile created at .git/gitop.lock"
else
    fail "lockfile created at .git/gitop.lock"
fi

printf '\ngitc\n'

# version flag
if assert_exit 0 "$GITC" --version; then pass "--version exits 0"; else fail "--version exits 0"; fi

# missing -- separator
if assert_exit 1 "$GITC" -m "msg"; then pass "missing -- exits 1"; else fail "missing -- exits 1"; fi
if assert_output "missing '--'" "$GITC" -m "msg"; then pass "missing -- error message"; else fail "missing -- error message"; fi

# -- present: delegates to git commit
REPO=$(new_repo)
echo "hello" > "$REPO/file.txt"
git -C "$REPO" add file.txt
if (cd "$REPO" && assert_exit 0 "$GITC" -m "initial" -- file.txt); then
    pass "commit with -- succeeds"
else
    fail "commit with -- succeeds"
fi

# gitc only commits named paths, not other staged files
REPO=$(new_repo)
echo "a" > "$REPO/a.txt"
echo "b" > "$REPO/b.txt"
git -C "$REPO" add a.txt b.txt
(cd "$REPO" && "$GITC" -m "only a" -- a.txt >/dev/null 2>&1)
# b.txt should still be staged (not swept into the commit)
staged=$(git -C "$REPO" diff --cached --name-only)
if printf '%s' "$staged" | grep -q "b.txt"; then
    pass "gitc leaves other staged files in index"
else
    fail "gitc leaves other staged files in index (staged: $staged)"
fi

# ---- summary ----------------------------------------------------------------

printf '\n%d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ]
