{ sources ? import ./sources.nix, pkgs ? (import sources.nixpkgs { }) }:

let
  t = pkgs.lib.trivial;
  hl = pkgs.haskell.lib;

  deps = [
    pkgs.git # Necessary to compile KMonad, but not to run it.
  ] ++ pkgs.lib.optional pkgs.stdenv.hostPlatform.isDarwin pkgs.darwin.apple_sdk.frameworks.IOKit;
in
pkgs.haskellPackages.developPackage {

  root = ./..;
  name = "kmonad";
    
  modifier = (t.flip t.pipe) ([
    (drv: hl.addBuildDepends drv deps) # Insert our buildDepends
    hl.justStaticExecutables # Only build the executable

    # TODO: investigate these here: https://github.com/NixOS/nixpkgs/blob/master/pkgs/development/haskell-modules/lib.nix
    # hl.dontHaddock
    # hl.enableStaticLibraries
    # hl.disableLibraryProfiling
    # hl.disableExecutableProfiling
    #
    # Maybe I make multiple targets, 1 for the executable, 1 for the hackage docs?
  ] ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
    (drv: hl.enableCabalFlag drv "dext")
    (drv: hl.appendConfigureFlag drv "--extra-include-dirs=c_src/mac/Karabiner-DriverKit-VirtualHIDDevice/include/pqrs/karabiner/driverkit:c_src/mac/Karabiner-DriverKit-VirtualHIDDevice/src/Client/vendor/include")
  ]);
}
