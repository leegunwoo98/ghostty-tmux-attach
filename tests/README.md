# tests/

Bats-based test suite for ghostty-tmux-attach.

## Layout

```
tests/
├── bats/             bats-core (submodule, pinned to v1.11.0)
├── bats-support/     test-helpers submodule
├── bats-assert/      assertion library submodule
├── bats-file/        file-state assertions submodule
├── helpers/
│   ├── common.bash       loaded by every .bats — REPO_ROOT, custom assertions
│   ├── sandbox.bash      sandboxed $HOME helpers
│   └── stubs.bash        tmux/Ghostty/date command stubs
├── fixtures/         shared sample files (Ghostty configs, tmux.confs)
├── unit/             pure-function tests (allocator helpers, set-merge, patches)
├── integration/      install/uninstall/update against sandboxed $HOME
├── race/             concurrency / TOCTOU / multi-process
└── e2e/              full launcher → tmux flow with stubbed Ghostty
```

## Writing a test

Every `.bats` file starts with:

```bash
#!/usr/bin/env bats

load '../helpers/common'
load '../helpers/sandbox'
load '../helpers/stubs'

setup() {
  sandbox_setup
  stubs_setup
}

teardown() {
  stubs_teardown
  sandbox_teardown
}

@test "describe the behavior" {
  # arrange
  sandbox_seed_ghostty_config
  stub_tmux_no_sessions

  # act
  run "$REPO_ROOT/install.sh" doctor

  # assert
  assert_success
  assert_output --partial "OS:"
}
```

`load` paths are resolved relative to the .bats file's directory. Tests live one
level under `tests/` (e.g. `tests/unit/foo.bats`), so helpers are at `../helpers/`.

## Running

```sh
make test               # all categories
make test-unit          # just unit tests
tests/run.sh integration
```

Bats supports `--filter` for running a single test by name:

```sh
tests/bats/bin/bats --filter "patches" tests/unit/
```

## Conventions

1. **One behavior per `@test`.** Use multiple `assert_*` lines, not nested cases.
2. **Sandbox everything.** Never write to real `$HOME`. Use `sandbox_setup`/`sandbox_teardown`.
3. **Stub external commands.** Don't depend on real tmux/Ghostty in unit tests. Use `tests/e2e/` for integration with real binaries.
4. **One test file per source unit.** `lib/allocator.sh` ↔ `tests/unit/allocator.bats`.
5. **TDD discipline.** Red → Green → Refactor → Commit. The test goes in the commit BEFORE the implementation.
6. **Race tests use small N + retries.** Pure timing-based tests are flaky; prefer property assertions (all N processes get distinct names).
7. **No real network.** CI runs offline. Any URL fetch is mocked.

## Coverage

v0.1 doesn't gate on coverage numbers. v0.2 may add `kcov` (Linux) for bash line coverage.

## Mutation

v0.1 doesn't include mutation testing. Worth revisiting if false-confidence shows up.
