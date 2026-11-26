//! Writes the greeting as a constant: the one in greeting.txt, if the source has it. The
//! split-build checks add that file, and a stub must not stand in for this script.

use std::{env, fs, path::Path};

fn main() {
    println!("cargo:rerun-if-changed=greeting.txt");
    let greeting = fs::read_to_string("greeting.txt").unwrap_or_else(|_| "Hello".into());
    let code = format!("/// The greeting.\npub const GREETING: &str = {:?};\n", greeting.trim());
    fs::write(Path::new(&env::var("OUT_DIR").unwrap()).join("greeting.rs"), code).unwrap();
}
