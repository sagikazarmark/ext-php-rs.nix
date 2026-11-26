fn main() {
    // The split-build check adds this source file on the second build.
    if std::path::Path::new("src/edited.rs").exists() {
        println!("cargo:rustc-cfg=edited");
    }
    println!("cargo:rustc-check-cfg=cfg(edited)");
}
