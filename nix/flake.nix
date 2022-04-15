{
  description = "An advanced keyboard manager";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-21.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let kmonad = import ./default.nix;
    in flake-utils.lib.eachDefaultSystem (system:
      let pkgs = nixpkgs.legacyPackages.${system};
      in rec {
        packages.kmonad = pkgs.haskellPackages.callPackage kmonad { };

        defaultPackage = packages.kmonad;

        devShell = pkgs.haskellPackages.shellFor {
          packages = _: [ packages.kmonad ];
          withHoogle = true;
          buildInputs = [ pkgs.haskellPackages.cabal-install ];
        };
      }) // rec {
        nixosModule = ({ ... }: {
          nixpkgs.overlays = [ self.overlay ];
          imports = [ (import ./module-base.nix { isDarwin = false; }) ];
        });
        darwinModule = ({ ... }: {
          nixpkgs.overlays = [ self.overlay ];
          imports = [ (import ./module-base.nix { isDarwin = true; }) ];
        });

        overlay = final: prev: {
          kmonad = final.haskellPackages.callPackage kmonad { };
        };
      };
}
