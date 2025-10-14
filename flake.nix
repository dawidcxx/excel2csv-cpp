{

  description = "Basic C++ project using Zig as build system with clangd support";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        lib = nixpkgs.lib;
        composeLibraryPath =
          packages: lib.concatStringsSep ":" (map (pkg: "${pkg.out or pkg}/lib") packages);
        composeIncludePath =
          packages: lib.concatStringsSep ":" (map (pkg: "${pkg.dev or pkg}/include") packages);
      in
      {
        devShells = {
          default = pkgs.mkShell.override { stdenv = pkgs.clangStdenv; } {
            nativeBuildInputs = with pkgs; [
              # Dev tools
              zig_0_15
              zls_0_15
              pkg-config # zig uses this for .linkSystemLibrary()
              clang-tools
              lldb

              # Libraries
              minizip
              zlib
              expat
              doctest
              jemalloc
            ];

            shellHook = ''
              unset NIX_CFLAGS_COMPILE
              export FLAKE_INCLUDES="${
                composeIncludePath [
                  pkgs.minizip
                  pkgs.zlib
                  pkgs.expat
                  pkgs.doctest
                ]
              }"
            '';
          };
        };
      }
    );
}
