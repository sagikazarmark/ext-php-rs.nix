//! A test fixture: hello_world(string $name): string, greeting as the workspace's other crate
//! says.

// The functions #[php_module] generates have no documentation.
#![allow(missing_docs)]

use ext_php_rs::prelude::*;

#[php_function]
pub fn hello_world(name: &str) -> String {
    format!("{}, {name}!", greeting::GREETING)
}

#[php_module]
pub fn get_module(module: ModuleBuilder) -> ModuleBuilder {
    module.function(wrap_function!(hello_world))
}
