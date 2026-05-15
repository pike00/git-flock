# git-flock

Two small tools that prevent concurrent and sequential git corruption when multiple processes share a repository.

```
gitop 'git add foo.yml && gitc -m "add foo" -- foo.yml && git push'
```

## The problem

When multiple agents, terminals, or CI jobs run `git add/commit/push` concurrently in the same repository, they race on `.git/index.lock`:

```
Another git process seems to be running in this repository.
```

Slow pre-commit hooks make it worse: one process holds the lock for minutes while others fail immediately.

There is a second, independent failure mode: a bare `git commit -m "msg"` absorbs **every currently staged file**, not just the ones you intended. If another session staged files earlier, your commit silently sweeps them up too.

## The solution

`git-flock` provides two tools that address each failure mode independently:

| Tool | Guards against |
|------|----------------|
| `gitop` | Concurrent races — serializes via `flock(1)` on `.git/gitop.lock` |
| `gitc` | Sequential sweeps — wraps `git commit`, requires explicit `--` pathspec |

Together:

```sh
gitop 'git add report.md && gitc -m "add report" -- report.md && git push'
#      ^--- one process at a time          ^--- only report.md in this commit
```

## Install

**Requirements:** POSIX sh, `git`, `flock(1)` (Linux: ships with util-linux; macOS: `brew install util-linux`)

```sh
git clone https://github.com/pike00/git-flock
cd git-flock
./install.sh        # installs to ~/.local/bin
```

Or manually copy `bin/gitop` and `bin/gitc` anywhere on your `$PATH`.

## Usage

### gitop

Wrap any git operation sequence in `gitop` to serialize it across all concurrent callers in the same repository:

```sh
# Single command
gitop git status

# Compound command (common case)
gitop 'git add foo.yml && gitc -m "add foo" -- foo.yml && git push'

# Fail fast in scripts
GITOP_WAIT=10 gitop 'gitc -m "fix" -- file.py && git push'
```

The lock file lives at `$REPO/.git/gitop.lock` (auto-created, safe to leave on disk). It is released the moment the inner command exits, whether it succeeds or fails.

**Reentrancy:** `gitop` sets `GITOP_HELD` in the environment for the duration of the locked command. Nested `gitop` calls detect this and run inline without re-acquiring the lock — no deadlock possible.

**Environment variables:**

| Variable | Default | Meaning |
|----------|---------|---------|
| `GITOP_WAIT` | `300` | Seconds to wait per lock attempt |
| `GITOP_MAX_RETRIES` | `10` | Maximum retries after timeout (total max wait: `WAIT × RETRIES`) |

### gitc

A drop-in replacement for `git commit` that enforces the `--` pathspec separator:

```sh
# correct — commits only file1 and file2
gitc -m "msg" -- file1 file2

# rejected — missing --
gitc -m "msg"
# gitc: missing '--' separator.
# usage: gitc [git-commit-opts] -- <file>...
```

All other `git commit` flags work as normal (`--amend`, `--no-edit`, `-S`, etc.). `gitc` is a thin wrapper; it calls `exec git commit "$@"` after validating the separator is present.

## Why both?

They guard against different failure modes and are useful independently:

- `gitop` alone still lets a commit sweep pre-staged files.
- `gitc` alone still lets two concurrent sessions collide on `index.lock`.

Using both together closes both gaps.

## How it works

### gitop

```
gitop 'cmd'
  └─ flock -x -w 300 $REPO/.git/gitop.lock -c 'cmd'
       └─ cmd runs with GITOP_HELD=$REPO set
            └─ if cmd calls gitop again → reentrancy check fires → no re-lock
```

`flock(1)` is a Linux kernel primitive (`flock(2)` syscall). It is advisory, process-scoped, and released automatically when the holding process exits — even on crash. There is no lock cleanup step.

### gitc

```
gitc -m "msg" -- file1 file2
  └─ scan argv for "--"
       ├─ found → exec git commit -m "msg" -- file1 file2
       └─ missing → error + exit 1
```

The `--` separator activates git's pathspec mode: the commit is built from the listed paths only, regardless of what else is currently staged. See `git-commit(1)` under `PATHSPEC`.

## Running tests

```sh
./tests/test.sh
# or
just test
```

The test suite creates temporary git repositories, exercises both tools, and verifies serialization timing.

## License

MIT
