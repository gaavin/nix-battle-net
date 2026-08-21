{
  description = "Declarative Battle.net launcher on Nix (umu-launcher + external Proton)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    {
      self,
      nixpkgs,
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      packages = rec {
        battle-net = pkgs.callPackage ./pkgs/battle-net { };
        default = battle-net;
      };
    in
    {
      packages.${system} = packages;

      apps.${system}.default = {
        type = "app";
        program = "${packages.battle-net}/bin/battle-net";
      };

      homeModules.battle-net =
        { lib, pkgs, ... }:
        {
          imports = [ ./modules/home-manager/battle-net.nix ];
          programs.battle-net.package = lib.mkDefault (
            self.packages.${pkgs.stdenv.hostPlatform.system}.battle-net
          );
        };
      homeModules.default = self.homeModules.battle-net;

      overlays.default = final: _prev: {
        inherit (self.packages.${final.stdenv.hostPlatform.system} or packages) battle-net;
      };
    };
}
