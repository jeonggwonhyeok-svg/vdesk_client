use std::env;
use std::path::{Path, PathBuf};
use bindgen::{Builder, RustTarget};

fn main() {
    println!("cargo:rustc-link-lib=kcp");
    let dir = env::var("CARGO_MANIFEST_DIR").unwrap();
    let fulldir = Path::new(&dir).join("kcp");

    let mut config = cc::Build::new();
    config.include(fulldir.clone());
    config.file(fulldir.join("ikcp.c"));
    config.opt_level(3);
    config.warnings(false);
    config.compile("libkcp.a");
    println!("cargo:rustc-link-search=native={}", fulldir.display());

    println!("cargo:rerun-if-changed=kcp/ikcp.h");
    println!("cargo:rerun-if-changed=kcp/ikcp.c");
    println!("cargo:rerun-if-changed=wrapper.h");

    let extra_header_path = std::env::var("KCP_SYS_EXTRA_HEADER_PATH").unwrap_or_default();
    let extra_header_paths = extra_header_path.split(":").filter(|s| !s.is_empty()).collect::<Vec<_>>();

    let mut builder = bindgen::Builder::default()
        .header("wrapper.h")
        .rust_target(RustTarget::Stable_1_73)
        .parse_callbacks(Box::new(bindgen::CargoCallbacks::new()))
        .clang_args(extra_header_paths.iter().map(|p| format!("-I{}", p)))
        .allowlist_function("ikcp_.*")
        .use_core();

    // Android cross-compile on macOS: add NDK sysroot for bindgen
    if let Ok(ndk) = env::var("ANDROID_NDK_HOME") {
        let target_os = env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
        if target_os == "android" {
            let host = if cfg!(target_os = "macos") { "darwin-x86_64" } else { "linux-x86_64" };
            let sysroot = format!("{}/toolchains/llvm/prebuilt/{}/sysroot", ndk, host);
            builder = builder
                .clang_arg(format!("--sysroot={}", sysroot))
                .clang_arg(format!("-isystem{}/usr/include", sysroot))
                .clang_arg(format!("-isystem{}/usr/include/aarch64-linux-android", sysroot));
        }
    }

    let bindings = builder
        .generate()
        .expect("Unable to generate bindings");

    let out_path = PathBuf::from(env::var("OUT_DIR").unwrap());
    bindings
        .write_to_file(out_path.join("bindings.rs"))
        .expect("Couldn't write bindings!");
}
