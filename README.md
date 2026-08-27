<div align="center">

# nix-battle-net

**Battle.net on NixOS** — umu-launcher plus an external Proton. Recommended: `proton-cachyos` from [Chaotic-Nyx](https://github.com/chaotic-cx/nyx).

[![NixOS](https://img.shields.io/badge/NixOS-unstable-informational?logo=NixOS)](https://nixos.org)
[![Flake](https://img.shields.io/badge/Flake-enabled-success)](https://nixos.wiki/wiki/Flakes)

</div>

## Quick Start

Point `PROTONPATH` at a Steam compat tool (`steamcompattool` output):

```bash
PROTONPATH=/path/to/proton nix run github:gaavin/nix-battle-net
```

Requires `x86_64-linux`, flakes, and a Proton already on the system. This flake does not vendor Proton. Prefer [Chaotic-Nyx](https://github.com/chaotic-cx/nyx)'s `proton-cachyos` (see below).

## Install with Home Manager

### 1. Add to flake inputs

```nix
{
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";

    nix-battle-net.url = "github:gaavin/nix-battle-net";
    nix-battle-net.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, home-manager, chaotic, nix-battle-net, ... }:
    {
      nixosConfigurations.YOUR_CONFIGURATION = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./configuration.nix
          chaotic.nixosModules.default
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = { inherit nix-battle-net; };
              users.YOUR_USERNAME = import ./home.nix;
            };
          }
        ];
      };
    };
}
```

### 2. Enable in `home.nix`

Recommended Proton is [`proton-cachyos`](https://www.nyx.chaotic.cx/) from Chaotic-Nyx. After importing `chaotic.nixosModules.default` (above), it is `pkgs.proton-cachyos`. Other Steam compatibility tools with a `steamcompattool` output (for example `pkgs.proton-ge-bin`) also work.

```nix
{ nix-battle-net, pkgs, ... }:
{
  imports = [ nix-battle-net.homeModules.battle-net ];

  programs.battle-net = {
    enable = true;
    protonVersion = pkgs.proton-cachyos; # Chaotic-Nyx
  };
}
```

### 3. Build & launch

```bash
nix flake update nix-battle-net
sudo nixos-rebuild switch --flake .#YOUR_CONFIGURATION
battle-net
```

First run downloads the installer and creates a Proton prefix. Finish the installer UI, then run `battle-net` again if the launcher did not start.

## Commands

| Command | Purpose |
|---------|---------|
| `battle-net` | Launch |
| `battle-net --help` | List all commands |
| `battle-net --info` | Show config / paths |
| `battle-net --kill` | Force quit |
| `battle-net --fix-agent` | Clear a stuck Battle.net Agent |
| `battle-net --winecfg` | Wine settings |
| `battle-net --winetricks …` | winetricks in the prefix |
| `battle-net --umu …` | Pass args to umu-run |

## Paths

```
~/.local/share/nix-battle-net/
  prefix/       Proton / Wine prefix
  installer/    Battle.net-Setup.exe
  logs/         Debug logs
```

Proton comes from `protonVersion` (or `PROTONPATH`). Battle.net auto-updates inside the prefix.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| White / blank window | `battle-net --kill`, then launch again |
| Tray is its own window | Leave `enableProtonWayland` off (default) |
| Agent stuck / `BLZBNTBNA00000005` | `battle-net --fix-agent`, then launch again |
| Proton not found | Add Chaotic-Nyx and set `programs.battle-net.protonVersion = pkgs.proton-cachyos` |
| DX12: no valid video card | Leave `useWineD3D` off (default), then restart Battle.net |
| Stuck Wine processes | `battle-net --kill` |
| Start fresh | Remove `~/.local/share/nix-battle-net/` |

## Advanced

Package only:

```nix
home.packages = [
  (inputs.nix-battle-net.packages.${pkgs.stdenv.hostPlatform.system}.battle-net.override {
    protonVersion = pkgs.proton-cachyos;
  })
];
```

Overrides:

```nix
inputs.nix-battle-net.packages.${pkgs.stdenv.hostPlatform.system}.battle-net.override {
  location = "$HOME/Games/Battlenet";
  protonVersion = pkgs.proton-cachyos;
  useGameMode = true;
  preLaunchArgs = "mangohud";
}
```

```bash
nix build github:gaavin/nix-battle-net#battle-net
```

## Credits

- [Open-Wine-Components/umu-launcher](https://github.com/Open-Wine-Components/umu-launcher) — Proton outside Steam
- [CachyOS/proton-cachyos](https://github.com/CachyOS/proton-cachyos) — Proton build this is written against
- [chaotic-cx/nyx](https://github.com/chaotic-cx/nyx) — recommended package: `proton-cachyos`
- [different-name/steam-config-nix](https://github.com/different-name/steam-config-nix) — Proton compat-tool path layout
- [ptrj/battle.net-on-linux](https://github.com/ptrj/battle.net-on-linux) — launcher env / Agent workaround
