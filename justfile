# rust-base template app: development tasks. Run `just` to see them.
# Shared recipes (dev, dev-signed, build, build-signed, install-signed, check,
# test-core, format, version, version-check, rust, frontend, ci, sweep) come from
# ci/common.just. Apps import their rust-base clone instead:
# `import? '~/.rust-base/ci/common.just'`. Don't redefine those names here.
import 'ci/common.just'

# Show available recipes.
default:
    @just --list

# Run the opt-in integration tests (#[ignore]d; need external systems). Run by the nightly workflow.
test-integration:
    cargo test --workspace -- --ignored
