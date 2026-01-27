# librusty_v8 - Rust bindings to V8, built from source
#
# This build script compiles V8 and its Rust bindings from source instead of
# downloading prebuilt binaries. The build process:
#
# 1. Fetches rusty_v8 source with submodules (includes V8 source)
# 2. Uses V8_FROM_SOURCE=1 to trigger compilation from source
# 3. Compiles V8 using gn + ninja (takes 30+ minutes)
# 4. Builds Rust bindings with cargo
# 5. Extracts the resulting librusty_v8.a static library
#
# The output is a single .a file that can be used with RUSTY_V8_ARCHIVE
# environment variable by packages like deno.
#
# Build requirements based on:
# - rusty_v8 README.md: https://github.com/denoland/rusty_v8
# - Chromium build patterns in nixpkgs (similar V8 dependencies)
#
# Note: This is a resource-intensive build requiring:
# - 30+ minutes compile time (depending on hardware)
# - Significant disk space for V8 source and build artifacts
# - Clang 19+ for bindgen (V8's libc++ builtin type traits)

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
  
  # Build the rusty_v8 crate which compiles V8 from source
  rusty_v8_build = rustPlatform.buildRustPackage rec {
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

    # Install the full build tree so we can extract the static library later
    installPhase = ''
      runHook preInstall
      
      # Create output directory with the build artifacts
      mkdir -p $out
      
      # Copy the entire target directory to preserve the build structure
      cp -r target $out/
      
      runHook postInstall
    '';

    meta = {
      description = "Rust bindings to V8 - built from source (intermediate build)";
      homepage = "https://github.com/denoland/rusty_v8";
      license = lib.licenses.mit;
      maintainers = with lib.maintainers; [ ];
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
    };
  };
in
# Extract just the static library as a single file for RUSTY_V8_ARCHIVE
stdenv.mkDerivation {
  pname = "librusty_v8";
  inherit (rusty_v8_build) version;
  
  dontUnpack = true;
  dontBuild = true;
  
  installPhase = ''
    # Find the static library in the build output
    libfile=$(find ${rusty_v8_build}/target -name "librusty_v8.a" -type f | head -n 1)
    
    if [ -z "$libfile" ]; then
      echo "Error: librusty_v8.a not found in build output!"
      echo "Available .a files:"
      find ${rusty_v8_build}/target -name "*.a" -type f
      exit 1
    fi
    
    echo "Found librusty_v8.a at: $libfile"
    
    # Copy the static library as a single file output
    # This matches what deno's RUSTY_V8_ARCHIVE expects
    cp "$libfile" $out
  '';
  
  meta = {
    description = "Rust bindings to V8 - built from source";
    homepage = "https://github.com/denoland/rusty_v8";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ ];
    # Building V8 from source requires significant resources and time
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
