//! IPC command modules. Each command is a thin (de)serialization shim over
//! [`app_core::Core`]; no domain logic lives here.

pub mod greet;
pub mod notes;
