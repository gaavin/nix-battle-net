{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    concatStringsSep
    escapeShellArg
    literalExpression
    mapAttrsToList
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  cfg = config.programs.battle-net;
in
{
  options.programs.battle-net = {
    enable = mkEnableOption "Battle.net (umu-launcher + external Proton via nix-battle-net)";

    package = mkOption {
      type = types.nullOr types.package;
      default = null;
      defaultText = literalExpression "nix-battle-net.packages.\${pkgs.stdenv.hostPlatform.system}.battle-net";
      example = literalExpression "nix-battle-net.packages.\${pkgs.stdenv.hostPlatform.system}.battle-net";
      description = ''
        battle-net package to install. When you import
        `nix-battle-net.homeModules.battle-net` from the flake, this defaults
        to that flake's `battle-net` — you usually do not need to set it.
      '';
    };

    protonVersion = mkOption {
      type = types.nullOr types.package;
      default = null;
      example = literalExpression "pkgs.proton-cachyos";
      description = ''
        Proton build passed to umu-launcher as PROTONPATH. Must be a Steam
        compatibility tool with a `steamcompattool` output (proton-cachyos,
        proton-ge-bin, and similar). Required when the module is enabled.
      '';
    };

    location = mkOption {
      type = types.str;
      default = "${config.xdg.dataHome}/nix-battle-net";
      defaultText = literalExpression "\${config.xdg.dataHome}/nix-battle-net";
      description = "Mutable state directory (Proton prefix, installer, logs).";
    };

    gamemode = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Wrap launches with gamemoderun. Requires a working GameMode daemon
        (e.g. programs.gamemode.enable on NixOS).
      '';
    };

    useWineD3D = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Set PROTON_USE_WINED3D=1 for the Battle.net launcher. Helps the CEF
        login window on Wayland. Turn off if a game launched from Battle.net
        needs DXVK and is stuck on wined3d.
      '';
    };

    environment = mkOption {
      type = types.attrsOf types.str;
      default = {
        GAMEID = "umu-battlenet";
        STORE = "battlenet";
        WINE_SIMULATE_WRITECOPY = "1";
        WINEDLLOVERRIDES = "locationapi=d";
        PROTON_USE_NTSYNC = "1";
      };
      example = {
        PROTON_ENABLE_WAYLAND = "1";
        MANGOHUD = "1";
      };
      description = "Environment variables written to the generated config and sourced at launch.";
    };

    preLaunchArgs = mkOption {
      type = types.str;
      default = "";
      example = "mangohud";
      description = "Programs prepended before umu-run (e.g. mangohud). gamemode is separate.";
    };

    extraConfig = mkOption {
      type = types.lines;
      default = "";
      description = "Raw lines appended to the generated env config file.";
    };
  };

  config = mkIf cfg.enable (
    let
      envFile = pkgs.writeText "nix-battle-net.env" (
        concatStringsSep "\n" (
          mapAttrsToList (k: v: "${k}=${escapeShellArg v}") cfg.environment
          ++ lib.optional cfg.useWineD3D "PROTON_USE_WINED3D=${escapeShellArg "1"}"
          ++ lib.optional (cfg.preLaunchArgs != "") "PRE_LAUNCH_ARGS=${escapeShellArg cfg.preLaunchArgs}"
          ++ lib.optional (cfg.extraConfig != "") cfg.extraConfig
        )
        + "\n"
      );

      finalPackage =
        if cfg.package == null then
          null
        else
          cfg.package.override {
            location = cfg.location;
            useGameMode = cfg.gamemode;
            useWineD3D = cfg.useWineD3D;
            protonVersion = cfg.protonVersion;
            configFile = envFile;
          };
    in
    {
      home.packages = lib.optional (finalPackage != null) finalPackage;

      assertions = [
        {
          assertion = cfg.package != null;
          message = ''
            programs.battle-net.package is unset. Import nix-battle-net.homeModules.battle-net
            from the flake (which sets a default), or set package explicitly to
            nix-battle-net.packages.''${pkgs.stdenv.hostPlatform.system}.battle-net.
          '';
        }
        {
          assertion = cfg.protonVersion != null;
          message = ''
            programs.battle-net.protonVersion is unset. Set it to a Steam
            compatibility tool package with a steamcompattool output, for example
            pkgs.proton-cachyos.
          '';
        }
      ];
    }
  );
}
