{ ... }:

{
  nixpkgs.overlays = [ (final: prev: { kmonad = import ./default.nix; }) ];
  imports = [ (import ./module-base.nix { isDarwin = true; }) ];
}
