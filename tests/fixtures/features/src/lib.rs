use ext_php_rs::prelude::*;

// Features for the build-options check: "Hello, <name>!" by default, "Hello, <name>." without
// the default features, and in capitals with "shout".
const PUNCTUATION: &str = if cfg!(feature = "exclaim") { "!" } else { "." };

#[php_function]
pub fn hello_world(name: &str) -> String {
    let greeting = format!("Hello, {name}{PUNCTUATION}");
    if cfg!(feature = "shout") {
        greeting.to_uppercase()
    } else {
        greeting
    }
}

#[php_module]
pub fn get_module(module: ModuleBuilder) -> ModuleBuilder {
    module.function(wrap_function!(hello_world))
}
