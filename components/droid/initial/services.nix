{
  lib,
  config,
  pkgs,
  ...
}:
{
  # Runit based service management
  options.services = {
    enable = lib.mkOption {
      type = lib.types.bool;
      description = "Whether to enable the services module.";
      default = false;
    };
    service-directory = lib.mkOption {
      type = lib.types.str;
      description = "Directory where service scripts are stored.";
      default = "${config.user.home}/../usr/var/services";
    };
    executables = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      description = "Executables to be built and added to PATH.";
      default = [ ];
      example = {
        sshd = "/path/to/sshd-start-script";
      };
    };
  };

  config = lib.mkIf config.services.enable (
    let
      serviceDirectory = config.services.service-directory;
    in
    {
      build.activation.services = ''
        if [[ ! -d "${serviceDirectory}" ]]; then
          $VERBOSE_ECHO "Creating service directory..."
          $DRY_RUN_CMD mkdir $VERBOSE_ARG --parents "${serviceDirectory}"
        fi

        ${lib.concatMapStringsSep "\n" (
          service:
          let
            serviceName = service;
            serviceBin = config.services.executables.${service};
            serviceFolder = "${serviceDirectory}/${serviceName}";
          in
          ''
            if [[ ! -d "${serviceFolder}" ]]; then
              $VERBOSE_ECHO "Creating service folder for ${serviceName}..."
              $DRY_RUN_CMD mkdir $VERBOSE_ARG --parents "${serviceFolder}"
            fi
            if [[ -L "${serviceFolder}/run" ]]; then
              currentTarget=$(readlink -f "${serviceFolder}/run")
              if [[ "$currentTarget" != "${serviceBin}" ]]; then
                $VERBOSE_ECHO "Updating symlink for ${serviceName}..."
                $DRY_RUN_CMD ln $VERBOSE_ARG --symbolic --force "${serviceBin}" "${serviceFolder}/run"
              fi
            else
              $VERBOSE_ECHO "Creating symlink for ${serviceName}..."
              $DRY_RUN_CMD ln $VERBOSE_ARG --symbolic --force "${serviceBin}" "${serviceFolder}/run"
            fi
          ''
        ) (lib.attrNames config.services.executables)}
      '';

      environment.packages = [
        pkgs.runit
        pkgs.tmux
        pkgs.procps
      ];

      environment.sessionVariables.SVDIR = serviceDirectory;

      # Start runsvdir via activation script (no shell hook in initial config)
      build.activation.runsvdir = ''
        ${pkgs.procps}/bin/pgrep -x runsvdir > /dev/null || \
          ${pkgs.tmux}/bin/tmux new-session -d -A -n daemons ${pkgs.runit}/bin/runsvdir -P "${serviceDirectory}"
      '';
    }
  );
}
