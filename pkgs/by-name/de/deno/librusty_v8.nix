{
  lib,
  stdenv,
  fetchFromGitHub,
  rustPlatform,
  python3,
  glib,
  pkg-config,
  llvmPackages_19,
  ninja,
  gn,
  git,
  curl,
  # Unused parameter kept for backward compatibility with package.nix
  fetchLibrustyV8 ? null,
}:

let
  # Python with packages required for V8 build scripts
  python3WithPackages = python3.withPackages (ps: with ps; [
    setuptools
  ]);
in
rustPlatform.buildRustPackage rec {
  pname = "librusty_v8";
  version = "142.2.0";

  src = fetchFromGitHub {
    owner = "denoland";
    repo = "rusty_v8";
    rev = "v${version}";
    hash = "sha256-kx+okpN6K1P5AJSEYUqVpATVvWAoKMwlP7sBj+fMm2I=";
    fetchSubmodules = true;
  };

  cargoHash = "sha256-ByLvvdbXxaKuZXj/9pCqeKE/jL9xxGa2t8WH/uG+v9Y=";

  nativeBuildInputs = [
    python3WithPackages
    pkg-config
    llvmPackages_19.clang
    llvmPackages_19.libclang
    ninja
    gn
    git
    curl # Required by build scripts for downloading dependencies
    rustPlatform.bindgenHook
  ];

  buildInputs = [
    glib
  ];

  # Build V8 from source instead of downloading prebuilt binaries
  # Based on rusty_v8 documentation and chromium build requirements
  env = {
    V8_FROM_SOURCE = "1";
    PYTHON = "${python3WithPackages}/bin/python3";
    LIBCLANG_PATH = "${llvmPackages_19.libclang.lib}/lib";
    # Provide preinstalled build tools to avoid downloads
    GN = "${gn}/bin/gn";
    NINJA = "${ninja}/bin/ninja";
    # Prevent Python from writing bytecode files
    PYTHONDONTWRITEBYTECODE = "1";
  };

  # V8 build takes a very long time and uses a lot of resources
  # Allow parallel building but cargo will manage it
  enableParallelBuilding = true;

  # Building V8 requires a lot of resources
  # Skip tests to reduce build time and resource usage
  doCheck = false;

  # Custom build phase to properly build the V8 library
  buildPhase = ''
    runHook preBuild
    
    # Build the library which will compile V8 from source
    # This can take 30+ minutes depending on the system
    cargo build --release --lib
    
    runHook postBuild
  '';

  # The output should be the compiled static library that deno expects
  installPhase = ''
    runHook preInstall
    
    # Create output directory
    mkdir -p $out
    
    # The static library is created by V8's gn/ninja build system
    # It should be in one of these locations depending on the target
    if [ -f "target/release/gn_out/obj/librusty_v8.a" ]; then
      cp target/release/gn_out/obj/librusty_v8.a $out/librusty_v8_release_${stdenv.hostPlatform.rust.rustcTarget}.a
    elif [ -f "target/${stdenv.hostPlatform.rust.rustcTarget}/release/gn_out/obj/librusty_v8.a" ]; then
      cp "target/${stdenv.hostPlatform.rust.rustcTarget}/release/gn_out/obj/librusty_v8.a" $out/librusty_v8_release_${stdenv.hostPlatform.rust.rustcTarget}.a
    else
      # Fallback: search for the library
      libfile=$(find target -name "librusty_v8.a" | head -n 1)
      if [ -n "$libfile" ]; then
        cp "$libfile" $out/librusty_v8_release_${stdenv.hostPlatform.rust.rustcTarget}.a
      else
        echo "Error: librusty_v8.a not found!"
        find target -name "*.a" -type f
        exit 1
      fi
    fi
    
    runHook postInstall
  '';

  meta = {
    description = "Rust bindings to V8 - built from source";
    homepage = "https://github.com/denoland/rusty_v8";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ ];
    # Building V8 from source requires significant resources and time
    # Only support platforms where this is practical
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
    # Note: This package takes a very long time to build (30+ minutes)
    # and requires significant disk space and memory
  };
}
