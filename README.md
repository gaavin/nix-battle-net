<div align="center">

# nix-battle-net

**Battle.net on NixOS** — umu-launcher plus an external Proton (proton-cachyos).

[![NixOS](https://img.shields.io/badge/NixOS-unstable-informational?logo=NixOS)](https://nixos.org)
[![Flake](https://img.shields.io/badge/Flake-enabled-success)](https://nixos.wiki/wiki/Flakes)

</div>

## ⚡ Quick Start

**Just want to try it?** Point `PROTONPATH` at a Steam compat tool (the `steamcompattool` output), then:

```bash
PROTONPATH=/path/to/proton-cachyos nix run github:gaavin/nix-battle-net
```

> **Requirements:** `x86_64-linux`, flakes enabled, Proton already installed (this flake does not vendor it).

---

## 📦 Install with Home Manager

### 1. Add to flake inputs

```nix
{
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-battle-net.url = "github:gaavin/nix-battle-net";
    nix-battle-net.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, home-manager, nix-battle-net, ... }:
    {
      nixosConfigurations.YOUR_CONFIGURATION = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./configuration.nix
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

`protonVersion` must be a Steam compatibility tool with a `steamcompattool` output — the same packages you would pass to Steam.

```nix
{ nix-battle-net, pkgs, ... }:
{
  imports = [ nix-battle-net.homeModules.battle-net ];

  programs.battle-net = {
    enable = true;
    protonVersion = pkgs.proton-cachyos;
    # Uncomment for custom options:
    # location = "${config.xdg.dataHome}/nix-battle-net";
    # gamemode = true;
    # useWineD3D = false;  # if a game needs DXVK and the launcher is already working
    # preLaunchArgs = "mangohud";
  };
}
```

### 3. Build & launch

```bash
nix flake update nix-battle-net
sudo nixos-rebuild switch --flake .#YOUR_CONFIGURATION
battle-net
```

✅ First run downloads the Battle.net installer and creates a Proton prefix  
✅ Finish the installer UI, then `battle-net` again if the launcher did not start  
✅ Desktop entry included

---

## 📋 Commands

| Command | Purpose |
|---------|---------|
| <span>battle-net</span> | Launch |
| <span>battle-net --help</span> | List all commands |
| <span>battle-net --info</span> | Show config / paths |
| <span>battle-net --kill</span> | Force quit |
| <span>battle-net --fix-agent</span> | Clear a stuck Battle.net Agent |
| <span>battle-net --winecfg</span> | Wine settings |
| <span>battle-net --winetricks …</span> | winetricks in prefix |
| <span>battle-net --umu …</span> | Pass args to umu-run |

---

## 📁 File Structure

```
~/.local/share/nix-battle-net/
  prefix/       Proton / Wine prefix
  installer/    Battle.net-Setup.exe
  logs/         Debug logs
```

Proton comes from `protonVersion` (or `PROTONPATH`). Battle.net itself auto-updates inside the prefix.

---

## 🔧 Troubleshooting

| Issue | Solution |
|-------|----------|
| Blank login window | Keep `useWineD3D = true` (default) and `WINE_SIMULATE_WRITECOPY=1` |
| Agent stuck / `BLZBNTBNA00000005` | `battle-net --fix-agent`, then launch again |
| Proton not found | Set `programs.battle-net.protonVersion = pkgs.proton-cachyos` |
| Game looks wrong / no DXVK | Set `useWineD3D = false` after the launcher login works |
| Stuck Wine processes | `battle-net --kill` |
| Start fresh | Remove `~/.local/share/nix-battle-net/` (installer + prefix re-created) |

---

## 🎮 Advanced

### Package only (skip Home Manager)

```nix
home.packages = [
  (inputs.nix-battle-net.packages.${pkgs.stdenv.hostPlatform.system}.battle-net.override {
    protonVersion = pkgs.proton-cachyos;
  })
];
```

### Custom overrides

```nix
inputs.nix-battle-net.packages.${pkgs.stdenv.hostPlatform.system}.battle-net.override {
  location = "$HOME/Games/Battlenet";
  protonVersion = pkgs.proton-cachyos;
  useGameMode = true;
  useWineD3D = true;
  preLaunchArgs = "mangohud";
}
```

```bash
nix build github:gaavin/nix-battle-net#battle-net
```

---

## 🙏 Credits

- [Open-Wine-Components/umu-launcher](https://github.com/Open-Wine-Components/umu-launcher) — Proton outside Steam
- [CachyOS/proton-cachyos](https://github.com/CachyOS/proton-cachyos) — Proton build this is written against
- [gaavin/nix-osu-stable](https://github.com/gaavin/nix-osu-stable) — packaging pattern
- [ptrj/battle.net-on-linux](https://github.com/ptrj/battle.net-on-linux) — launcher env / Agent workaround
