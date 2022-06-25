{
  description = "KMonad: An advanced keyboard manager.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    Karabiner-DriverKit-VirtualHIDDevice = {
      url = "github:pqrs-org/Karabiner-DriverKit-VirtualHIDDevice?rev=bfe93e7bdd13f766937becd640f91f4b0c02444f";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, Karabiner-DriverKit-VirtualHIDDevice }:
    let
      # List of supported systems:
      supportedSystems = [ "x86_64-linux" "x86_64-darwin" ];

      # List of supported compilers:
      supportedCompilers = [
        "ghc8107"
        "ghc902"
        "ghc922"
      ];

      # Function to generate a set based on supported systems:
      forAllSystems = f:
        nixpkgs.lib.genAttrs supportedSystems (system: f system);

      # Attribute set of nixpkgs for each system:
      nixpkgsFor = forAllSystems (system: import nixpkgs { inherit system; });

      # A source file list cleaner for Haskell programs:
      haskellSourceFilter = src:
        nixpkgs.lib.cleanSourceWith {
          inherit src;
          filter = name: type:
            let baseName = baseNameOf (toString name); in
            nixpkgs.lib.cleanSourceFilter name type &&
            !(
              baseName == "dist-newstyle"
              || nixpkgs.lib.hasPrefix "." baseName
            );
        };

      # A fake version of git which can be used during the build to
      # embed the current revision into the binary despite the .git
      # directory not being available:
      fakeGit = pkgs: pkgs.writeShellScriptBin "git" ''
        echo ${self.rev or "dirty"}
      '';

      # The package derivation:
      derivation = pkgs: haskell: (
        haskell.callCabal2nixWithOptions "kmonad" (haskellSourceFilter ../.)
          ((pkgs.lib.strings.optionalString pkgs.stdenv.hostPlatform.isDarwin
            # FIXME: remove the --no-check flag once tests are fixed
            "--flag=dext") + " --no-check")
          { }
      ).overrideAttrs (orig: {
        buildInputs = orig.buildInputs ++ [ (fakeGit pkgs) ] ++
          (pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
            pkgs.darwin.apple_sdk.frameworks.CoreFoundation
            pkgs.darwin.IOKit
          ]);
      } // (pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
        configureFlags = orig.configureFlags ++ [
          "--extra-include-dirs=c_src/mac/Karabiner-DriverKit-VirtualHIDDevice/src/Client/vendor/include"
          "--extra-include-dirs=c_src/mac/Karabiner-DriverKit-VirtualHIDDevice/include/pqrs/karabiner/driverkit"
        ];
        srcs = [ Karabiner-DriverKit-VirtualHIDDevice ];
        unpackPhase = ''
          cp -r "$src" src
          sourceRoot="$PWD/src"

          # allow writes in src/c_src/mac for the two copies
          chmod u+w src/c_src/mac
          rm -rf src/c_src/mac/Karabiner-DriverKit-VirtualHIDDevice
          cp -r "$srcs" src/c_src/mac/Karabiner-DriverKit-VirtualHIDDevice

          # make everything writable
          chmod -R u+w src
        '';
      }));
    in
    {
      packages = forAllSystems (system:
        let pkgs = nixpkgsFor.${system}; in
        {
          # The full Haskell package for the default compiler:
          kmonad = derivation pkgs pkgs.haskellPackages;

          # Just the executables for the default compiler:
          default = pkgs.haskell.lib.justStaticExecutables
            (derivation pkgs pkgs.haskellPackages);
        } // (pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
          list-keyboards = pkgs.stdenv.mkDerivation {
            name = "list-keyboards";
            version = self.shortRev;
            src = ../c_src/mac;
            buildInputs = [
              pkgs.darwin.apple_sdk.frameworks.CoreFoundation
              pkgs.darwin.IOKit
            ];
            installFlags = [ "DESTDIR=$(out)" ];
          };
        }) // builtins.listToAttrs (map
          (compiler: {
            name = "kmonad-${compiler}";
            value = derivation pkgs pkgs.haskell.packages.${compiler};
          })
          supportedCompilers));

      overlays.default = final: prev: {
        kmonad = self.packages.${prev.system}.default;
      };

      darwinModules.default = import ./darwin-module.nix;

      nixosModules.default = { ... }: {
        imports = [
          ./nixos-module.nix
          { nixpkgs.overlays = [ self.overlays.default ]; }
        ];
      };

      checks.x86_64-linux.default =
        let pkgs = nixpkgsFor.x86_64-linux; in
        import ./nixos-test.nix {
          inherit pkgs;
          module = self.nixosModules.default;
        };

      devShells = forAllSystems (system:
        let shellFor = haskell: name:
          haskell.shellFor {
            NIX_PATH = "nixpkgs=${nixpkgsFor.${system}.path}";

            packages = _: [ self.packages.${system}.${name} ];
            withHoogle = true;
            buildInputs = [
              haskell.cabal-install
              haskell.haskell-language-server
              haskell.hlint
              haskell.stack
            ];
          }; in
        {
          default = shellFor
            nixpkgsFor.${system}.haskellPackages
            "kmonad";
        } // builtins.listToAttrs (map
          (compiler: {
            name = "kmonad-${compiler}";
            value = shellFor
              nixpkgsFor.${system}.haskell.packages.${compiler}
              "kmonad-${compiler}";
          })
          supportedCompilers));
    };
}
