{ isDarwin }:
{ pkgs, config, lib, ... }:

let cfg = config.services.kmonad;
in

with lib;
{
  options.services.kmonad = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        If enabled, run kmonad after boot.
      '';
    };

    configfiles = mkOption {
      type = types.listOf types.path;
      default = [];
      example = "[ my-config.kbd ]";
      description = ''
        Config files for dedicated kmonad instances.
      '';
    };

    optionalconfigs = mkOption {
      type = types.listOf types.path;
      default = [];
      example = "[ optional.kbd ]";
      description = ''
        Config files for dedicated kmonad instances which may not always be present.
      '';
    };

    package = mkOption {
      type = types.package;
      default = pkgs.kmonad;
      example = "pkgs.kmonad";
      description = ''
        The kmonad package.
      '';
    };
  };

  config = {
    environment.systemPackages = [ cfg.package ];
  } // (if isDarwin then {
    launchd.user = with lib; with builtins;
      let
        mk-kmonad-service = { is-optional }: kbd-path:
          let
            # prettify the service's name by taking the config filename...
            conf-file = lists.last (strings.splitString "/" (toString kbd-path));
            # ...and dropping the extension
            conf-name = lists.head (strings.splitString "." conf-file);
          in
          {
            name = "kmonad-" + conf-name;
            value = {
              serviceConfig = {
                ProgramArguments = [ "${cfg.package}/bin/kmonad" (toString kbd-path) ];
                KeepAlive = true;
                RunAtLoad = true;
                Disabled = is-optional;
                Nice = -20;
                EnvironmentVariables = {
                  PATH = "${cfg.package}/bin:${config.environment.systemPath}";
                };
              };
            };
          };

        required-units = map (mk-kmonad-service { is-optional = false; }) cfg.configfiles;

        optional-units = map (mk-kmonad-service { is-optional = true; }) cfg.optionalconfigs;

      in
      mkIf cfg.enable {
        # convert our output [{name=_; value=_;}] map to {name=value;} for the systemd module
        agents = listToAttrs (required-units ++ optional-units);
      };
  } else {
    users.groups.uinput = { };

    services.udev.extrarules = mkIf cfg.enable
      ''
        # kmonad user access to /dev/uinput
        kernel=="uinput", mode="0660", group="uinput", options+="static_node=uinput"
      '';

    systemd = with lib; with builtins;
      let
        # if only one config file is supplied, unify all kmonad units under a target
        make-group = (length cfg.configfiles + length cfg.optionalconfigs) > 1;

        # all systemd units require the graphics target directly (if a single config),
        # or indirectly (via kmonad.target).
        wantedby = [ "graphical.target" ];

        mk-kmonad-target = services: {
          # the kmonad.target allows you to restart all kmonad instances with:
          #
          #     systemctl restart kmonad.target
          #
          # this works because this unit requires all config-based services
          description = "kmonad target";
          requires = map (service: service.name + ".service") services;
          inherit wantedby;
        };

        mk-kmonad-service = { is-optional }: kbd-path:
          let
            # prettify the service's name by taking the config filename...
            conf-file = lists.last (strings.splitString "/" (tostring kbd-path));
            # ...and dropping the extension
            conf-name = lists.head (strings.splitString "." conf-file);
          in
          {
            name = "kmonad-" + conf-name;
            value = {
              enable = true;
              description = "kmonad instance for: " + conf-name;
              serviceconfig = {
                type = "simple";
                restart = "always";
                restartsec = 3;
                nice = -20;
                execstart =
                  "${cfg.package}/bin/kmonad ${kbd-path}" +
                    # kmonad will error on initialization for any unplugged keyboards
                    # when run in systemd. all optional configs will silently error
                    #
                    # todo: maybe try to restart the unit?
                    (if is-optional then " || true" else "");
              };
            } // (if make-group
            then { partof = [ "kmonad.target" ]; }
            else { inherit wantedby; });
          };

        required-units = map (mk-kmonad-service { is-optional = false; }) cfg.configfiles;

        optional-units = map (mk-kmonad-service { is-optional = true; }) cfg.optionalconfigs;

      in
      mkIf cfg.enable ({
        # convert our output [{name=_; value=_;}] map to {name=value;} for the systemd module
        services = listToAttrs (required-units ++ optional-units);
      } // (
        # additionally, if make-group is true, add the targets.kmonad attr and pass in all units
        attrsets.optionalAttrs make-group
          { targets.kmonad = mk-kmonad-target (required-units ++ optional-units); }
      )
      );
  });
}
