{ config, lib, pkgs, ... }:

let
  cfg = config.services.kmonad;

  # Per-keyboard options:
  keyboard = { name, ... }: {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        example = "laptop-internal";
        description = "Keyboard name.";
      };

      device = lib.mkOption {
        type = lib.types.str;
        example = "Apple Internal Keyboard / Trackpad";
        # TODO: provide instructions for determining this
        description = "Product string of the keyboard.";
      };

      defcfg = {
        enable = lib.mkEnableOption ''
          Automatically generate the defcfg block.

          When this is option is set to true the config option for
          this keyboard should not include a defcfg block.
        '';

        compose = {
          key = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = "ralt";
            description = "The (optional) compose key to use.";
          };

          delay = lib.mkOption {
            type = lib.types.int;
            default = 5;
            description = "The delay (in milliseconds) between compose key sequences.";
          };
        };

        fallthrough = lib.mkEnableOption "Reemit unhandled key events.";

        allowCommands = lib.mkEnableOption "Allow keys to run shell commands.";
      };

      config = lib.mkOption {
        type = lib.types.lines;
        description = "Keyboard configuration.";
      };
    };

    config = {
      name = lib.mkDefault name;
    };
  };

  # Create a complete KMonad configuration file:
  mkCfg = keyboard:
    let
      defcfg = ''
        (defcfg
          input  (iokit-name "${keyboard.device}")
          output (dext)
      '' +
      lib.optionalString (keyboard.defcfg.compose.key != null) ''
        cmp-seq ${keyboard.defcfg.compose.key}
        cmp-seq-delay ${toString keyboard.defcfg.compose.delay}
      '' + ''
          fallthrough ${lib.boolToString keyboard.defcfg.fallthrough}
          allow-cmd ${lib.boolToString keyboard.defcfg.allowCommands}
        )
      '';
    in
    pkgs.writeTextFile {
      name = "kmonad-${keyboard.name}.cfg";
      text = lib.optionalString keyboard.defcfg.enable (defcfg + "\n") + keyboard.config;
      checkPhase = "${cfg.package}/bin/kmonad -d $out";
    };

  # Build a launchd daemon that starts KMonad:
  mkDaemon = keyboard:
    {
      name = "kmonad-${keyboard.name}";
      value = {
        serviceConfig = {
          EnvironmentVariables.PATH = config.environment.systemPath;
          KeepAlive = true;
          Nice = -20;
          ProgramArguments = [
            "${cfg.package}/bin/kmonad"
            "--input"
            ''iokit-name "${keyboard.device}"''
          ] ++ cfg.extraArgs ++ [
            "${mkCfg keyboard}"
          ];
          RunAtLoad = true;
        };
      };
    };
in
{
  options.services.kmonad = {
    enable = lib.mkEnableOption "KMonad: An advanced keyboard manager.";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.kmonad;
      example = "pkgs.haskellPackages.kmonad";
      description = "The KMonad package to use.";
    };

    keyboards = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule keyboard);
      default = { };
      description = "Keyboard configuration.";
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "--log-level" "debug" ];
      description = "Extra arguments to pass to KMonad.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    launchd.daemons =
      builtins.listToAttrs
        (map mkDaemon (builtins.attrValues cfg.keyboards));
  };
}
