{
  lib,
  makeDesktopItem,
  runCommand,
  symlinkJoin,
  writeShellApplication,
  writeText,
  umu-launcher,
  winetricks,
  coreutils,
  curl,
  wget,
  procps,
  gamemode,
  jq,
  pname ? "battle-net",
  location ? "$HOME/.local/share/nix-battle-net",
  useGameMode ? false,
  useWineD3D ? true,
  # Proton-CachyOS / Proton 11 CEF workaround for a white login window.
  launcherArgs ? "--in-process-gpu",
  disableHardwareAcceleration ? true,
  # Proton package (steamcompattool output, or Chaotic proton-cachyos with bin/).
  protonVersion ? null,
  configFile ? null,
  environment ? { },
  preLaunchArgs ? "",
}:

let
  inherit (lib)
    concatStringsSep
    escapeShellArg
    getExe
    getName
    getOutput
    mapAttrsToList
    optional
    optionalAttrs
    optionalString
    ;

  # Steam compat tools put proton + compatibilitytool.vdf at the root of the
  # steamcompattool output. Chaotic's proton-cachyos instead nests them under
  # bin/ and often has no steamcompattool output — same layout probe as
  # steam-config-nix (compatToolDir).
  protonCompatPath =
    if protonVersion == null then
      ""
    else
      let
        base = getOutput "steamcompattool" protonVersion;
      in
      runCommand "${getName protonVersion}-steamcompattool" {
        preferLocalBuild = true;
        allowSubstitutes = false;
      } ''
        if [ -e ${escapeShellArg "${base}/proton"} ] || [ -f ${escapeShellArg "${base}/compatibilitytool.vdf"} ]; then
          ln -s ${escapeShellArg base} "$out"
        elif [ -e ${escapeShellArg "${base}/bin/proton"} ] || [ -f ${escapeShellArg "${base}/bin/compatibilitytool.vdf"} ]; then
          ln -s ${escapeShellArg "${base}/bin"} "$out"
        else
          echo "nix-battle-net: no Proton compat tool found in ${base} or ${base}/bin" >&2
          exit 1
        fi
      '';

  extraCompatPaths = protonCompatPath;

  installerUrl = "https://downloader.battle.net/download/getInstallerForGame?os=win&gameProgram=BATTLENET_APP&version=Live";

  mergedEnvironment = {
    GAMEID = "umu-battlenet";
    STORE = "battlenet";
    WINE_SIMULATE_WRITECOPY = "1";
    WINEDLLOVERRIDES = "locationapi=d";
    PROTON_USE_NTSYNC = "1";
    LAUNCHER_ARGS = launcherArgs;
    DISABLE_BATTLENET_HWACCEL = if disableHardwareAcceleration then "1" else "0";
  }
  // optionalAttrs useWineD3D { PROTON_USE_WINED3D = "1"; }
  // environment
  // optionalAttrs (preLaunchArgs != "") { PRE_LAUNCH_ARGS = preLaunchArgs; };

  packagedConfig = writeText "nix-battle-net.env" (
    concatStringsSep "\n" (mapAttrsToList (k: v: "${k}=${escapeShellArg v}") mergedEnvironment) + "\n"
  );

  resolvedConfig = if configFile != null then configFile else packagedConfig;

  script = writeShellApplication {
    name = pname;
    runtimeInputs = [
      coreutils
      curl
      wget
      procps
      winetricks
      umu-launcher
      jq
    ]
    ++ optional useGameMode gamemode;

    text = ''
      set -euo pipefail

      LOCATION="''${LOCATION:-${location}}"
      LOCATION="''${LOCATION/#\~/$HOME}"
      STATE_DIR="$LOCATION"
      WINEPREFIX_DIR="$STATE_DIR/prefix"
      INSTALLER_DIR="$STATE_DIR/installer"
      LOG_DIR="$STATE_DIR/logs"
      CONFIG_FILE="''${BATTLE_NET_CONFIG:-${resolvedConfig}}"
      PACKAGED_PROTON="${protonCompatPath}"
      PACKAGED_COMPAT_PATHS="${extraCompatPaths}"
      INSTALLER_URL="''${BATTLE_NET_INSTALLER_URL:-${installerUrl}}"
      INSTALLER_EXE="$INSTALLER_DIR/Battle.net-Setup.exe"
      UMU_RUN=${escapeShellArg (getExe umu-launcher)}
      BATTLENET_EXE=""

      export WINEPREFIX="$WINEPREFIX_DIR"
      export GAMEID="''${GAMEID:-umu-battlenet}"
      export STORE="''${STORE:-battlenet}"

      if [ -r "$CONFIG_FILE" ]; then
        set -a
        # shellcheck disable=SC1090
        source "$CONFIG_FILE"
        set +a
      fi

      info() { printf '\033[1;34mnix-battle-net:\033[0m %s\n' "$*" >&2; }
      err() { printf '\033[1;31mnix-battle-net:\033[0m %s\n' "$*" >&2; }

      find_proton_dir() {
        local candidate="$1"
        if [ -e "$candidate/proton" ]; then
          printf '%s' "$candidate"
          return 0
        fi
        if [ -e "$candidate/bin/proton" ]; then
          printf '%s' "$candidate/bin"
          return 0
        fi
        return 1
      }

      resolve_proton() {
        local resolved=""
        if [ -n "''${PROTONPATH:-}" ]; then
          if ! resolved="$(find_proton_dir "$PROTONPATH")"; then
            err "PROTONPATH does not look like a Proton build: $PROTONPATH"
            err "Need a Steam compat tool directory containing a proton script (or bin/proton)."
            return 1
          fi
        elif [ -n "$PACKAGED_PROTON" ] && [ -d "$PACKAGED_PROTON" ]; then
          if ! resolved="$(find_proton_dir "$PACKAGED_PROTON")"; then
            err "Packaged Proton does not look like a Proton build: $PACKAGED_PROTON"
            err "Need a Steam compat tool directory containing a proton script (or bin/proton)."
            return 1
          fi
        else
          err "No Proton found."
          err "Set programs.battle-net.protonVersion (e.g. pkgs.proton-cachyos)"
          err "or export PROTONPATH to a Steam compat tool directory."
          return 1
        fi
        export PROTONPATH="$resolved"

        if [ -n "$PACKAGED_COMPAT_PATHS" ]; then
          if [ -n "''${STEAM_EXTRA_COMPAT_TOOLS_PATHS:-}" ]; then
            export STEAM_EXTRA_COMPAT_TOOLS_PATHS="$PACKAGED_COMPAT_PATHS:''${STEAM_EXTRA_COMPAT_TOOLS_PATHS}"
          else
            export STEAM_EXTRA_COMPAT_TOOLS_PATHS="$PACKAGED_COMPAT_PATHS"
          fi
        fi
      }

      run_umu() {
        local -a cmd=()
        ${optionalString useGameMode "cmd+=(${escapeShellArg "${gamemode}/bin/gamemoderun"})"}
        if [ -n "''${PRE_LAUNCH_ARGS:-}" ]; then
          local -a pre_args=()
          # shellcheck disable=SC2206
          read -r -a pre_args <<<"''${PRE_LAUNCH_ARGS}"
          cmd+=("''${pre_args[@]}")
        fi
        cmd+=("$UMU_RUN")
        exec "''${cmd[@]}" "$@"
      }

      battlenet_exe() {
        local c
        local candidates=(
          "$WINEPREFIX_DIR/drive_c/Program Files (x86)/Battle.net/Battle.net Launcher.exe"
          "$WINEPREFIX_DIR/drive_c/Program Files/Battle.net/Battle.net Launcher.exe"
          "$WINEPREFIX_DIR/drive_c/Program Files (x86)/Battle.net/Battle.net.exe"
          "$WINEPREFIX_DIR/drive_c/Program Files/Battle.net/Battle.net.exe"
        )
        for c in "''${candidates[@]}"; do
          if [ -s "$c" ]; then
            printf '%s' "$c"
            return 0
          fi
        done
        return 1
      }

      download_installer() {
        local tmp
        mkdir -p "$INSTALLER_DIR"
        if [ -s "$INSTALLER_EXE" ] && [ "$(head -c 2 "$INSTALLER_EXE")" = "MZ" ]; then
          return 0
        fi
        tmp="$(mktemp "$INSTALLER_EXE.XXXXXX.tmp")"
        info "Downloading Battle.net installer"
        info "  from: $INSTALLER_URL"
        info "  to:   $INSTALLER_EXE"
        if curl -fL --progress-bar -o "$tmp" "$INSTALLER_URL"; then
          :
        elif wget --show-progress -O "$tmp" "$INSTALLER_URL"; then
          :
        else
          rm -f "$tmp"
          err "Failed to download Battle.net installer (need network + curl/wget)"
          return 1
        fi
        if [ ! -s "$tmp" ] || [ "$(head -c 2 "$tmp")" != "MZ" ]; then
          rm -f "$tmp"
          err "Download does not look like a Windows executable"
          return 1
        fi
        mv -f "$tmp" "$INSTALLER_EXE"
        chmod u+rw "$INSTALLER_EXE"
        info "Installer ready ($(du -h "$INSTALLER_EXE" | cut -f1))"
      }

      ensure_prefix() {
        mkdir -p "$WINEPREFIX_DIR" "$LOG_DIR"
        if [ -r "$WINEPREFIX_DIR/system.reg" ]; then
          return 0
        fi
        info "Creating Proton prefix at $WINEPREFIX_DIR"
        "$UMU_RUN" wineboot -u || {
          err "umu-run failed to create the prefix"
          return 1
        }
      }

      ensure_battlenet() {
        if BATTLENET_EXE="$(battlenet_exe)"; then
          return 0
        fi
        download_installer
        ensure_prefix
        apply_cef_workarounds
        info "Running Battle.net installer — finish setup, then close it"
        "$UMU_RUN" "$INSTALLER_EXE" || true
        if BATTLENET_EXE="$(battlenet_exe)"; then
          return 0
        fi
        err "Battle.net Launcher.exe not found under $WINEPREFIX_DIR"
        err "Finish the installer, then run ${pname} again."
        return 1
      }

      kill_battlenet() {
        pkill -f 'Battle.net' 2>/dev/null || true
        pkill -f wineserver 2>/dev/null || true
      }

      # Battle.net's CEF login UI often paints a solid white window under Proton
      # on Wayland. Lutris writes HardwareAcceleration=false; Proton-CachyOS
      # recommends --in-process-gpu on the launcher exe.
      apply_cef_workarounds() {
        local cfg="$WINEPREFIX_DIR/drive_c/users/steamuser/AppData/Roaming/Battle.net/Battle.net.config"
        local tmp
        if [ "''${DISABLE_BATTLENET_HWACCEL:-1}" = "0" ]; then
          return 0
        fi
        mkdir -p "$(dirname "$cfg")"
        if [ -s "$cfg" ]; then
          tmp="$(mktemp)"
          if jq '.Client.HardwareAcceleration = "false"' "$cfg" > "$tmp" && [ -s "$tmp" ]; then
            mv -f "$tmp" "$cfg"
          else
            rm -f "$tmp"
            info "Could not update Battle.net.config"
          fi
        else
          printf '%s\n' '{"Client":{"HardwareAcceleration":"false"}}' > "$cfg"
        fi
      }

      prepare() {
        mkdir -p "$STATE_DIR" "$INSTALLER_DIR" "$LOG_DIR"
        resolve_proton
        export WINEPREFIX="$WINEPREFIX_DIR"
      }

      usage() {
        cat <<EOF
      Usage: ${pname} [command]

        (no args)         Launch Battle.net
        --help            Show this help
        --info            Show config / paths
        --kill            Force quit Battle.net / wineserver
        --fix-agent       Kill processes and remove a stuck Battle.net Agent
        --winecfg         Wine settings
        --winetricks …    winetricks in the prefix
        --umu <args>      Pass arguments to umu-run

      State: $STATE_DIR
      Config: $CONFIG_FILE
      EOF
      }

      case "''${1:-}" in
        --help|-h) usage; exit 0 ;;
        --info)
          prepare
          cat <<EOF
      State:      $STATE_DIR
      Wineprefix: $WINEPREFIX_DIR
      Proton:     ''${PROTONPATH:-}
      umu-run:    $UMU_RUN
      config:     $CONFIG_FILE
      installer:  $INSTALLER_URL
      launcher:   $(battlenet_exe 2>/dev/null || echo "(not installed)")
      EOF
          exit 0
          ;;
        --kill)
          kill_battlenet
          info "Stopped Battle.net / wineserver."
          exit 0
          ;;
        --fix-agent)
          prepare
          kill_battlenet
          rm -rf "$WINEPREFIX_DIR/drive_c/ProgramData/Battle.net"
          info "Removed Battle.net Agent data. Run ${pname} again."
          exit 0
          ;;
        --winecfg)
          prepare
          ensure_prefix
          exec "$UMU_RUN" winecfg
          ;;
        --winetricks)
          prepare
          ensure_prefix
          shift
          exec "$UMU_RUN" winetricks "$@"
          ;;
        --umu)
          prepare
          ensure_prefix
          shift
          exec "$UMU_RUN" "$@"
          ;;
        "")
          prepare
          ensure_battlenet
          apply_cef_workarounds
          info "Launching $BATTLENET_EXE"
          launcher_args=()
          if [ -z "''${LAUNCHER_ARGS+x}" ]; then
            launcher_args=(--in-process-gpu)
          elif [ -n "''${LAUNCHER_ARGS}" ]; then
            # shellcheck disable=SC2206
            read -r -a launcher_args <<<"''${LAUNCHER_ARGS}"
          fi
          run_umu "$BATTLENET_EXE" "''${launcher_args[@]}"
          ;;
        *)
          err "Unknown command: $1"
          usage
          exit 1
          ;;
      esac
    '';
  };

  desktopItem = makeDesktopItem {
    name = pname;
    exec = "${script}/bin/${pname}";
    icon = "nix-battle-net";
    comment = "Battle.net (umu-launcher + Proton)";
    desktopName = "Battle.net";
    categories = [ "Game" ];
  };

  iconShare = runCommand "nix-battle-net-icon" { } ''
    install -Dm644 ${../../assets/nix-battle-net.svg} \
      "$out/share/icons/hicolor/scalable/apps/nix-battle-net.svg"
  '';
in
symlinkJoin {
  name = pname;
  paths = [
    script
    desktopItem
    iconShare
  ];
  passthru = {
    inherit protonVersion protonCompatPath extraCompatPaths;
    envConfig = resolvedConfig;
    inherit installerUrl;
  };
  meta = {
    description = "Declarative Battle.net launcher using umu-launcher and an external Proton";
    homepage = "https://github.com/gaavin/nix-battle-net";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = pname;
  };
}
