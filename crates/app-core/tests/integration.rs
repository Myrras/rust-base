//! Opt-in integration tests: skipped by `cargo test`, run by `just test-integration`
//! (nightly workflow). Replace the example with tests against real external systems.

#[test]
#[ignore = "integration: needs an external system (example); run with just test-integration"]
fn external_system_example() {
    assert_eq!(2 + 2, 4);
}
