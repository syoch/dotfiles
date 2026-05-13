{ pkgs, config, ... }:
let
  sshdTmpDirectory = "${config.user.home}/../usr/var/sshd-tmp";
  sshdDirectory = "${config.user.home}/../usr/var/sshd";
  pubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILacK4KYMvzARCSG8v7H8KCeZIzXapkNB0ZwI70GaasV syoch-MyDevices";
  port = 8022;
in
{
  build.activation.sshd = ''
    $DRY_RUN_CMD mkdir $VERBOSE_ARG --parents "${config.user.home}/.ssh"
    $DRY_RUN_CMD echo ${pubkey} > "${config.user.home}/.ssh/authorized_keys"

    if [[ ! -d "${sshdDirectory}" ]]; then
      $DRY_RUN_CMD rm $VERBOSE_ARG --recursive --force "${sshdTmpDirectory}"
      $DRY_RUN_CMD mkdir $VERBOSE_ARG --parents "${sshdTmpDirectory}"

      $VERBOSE_ECHO "Generating host keys..."
      $DRY_RUN_CMD ${pkgs.openssh}/bin/ssh-keygen -t rsa -b 4096 -f "${sshdTmpDirectory}/ssh_host_rsa_key" -N ""

      $VERBOSE_ECHO "Writing sshd_config..."
      $DRY_RUN_CMD echo -e "HostKey ${sshdDirectory}/ssh_host_rsa_key\nPort ${toString port}\n" > "${sshdTmpDirectory}/sshd_config"

      $DRY_RUN_CMD mv $VERBOSE_ARG "${sshdTmpDirectory}" "${sshdDirectory}"
    fi
  '';

  services.executables.sshd =
    let
      sshdPath = "${pkgs.openssh}/bin/sshd";
      script = ''
        #!/bin/sh
        exec ${sshdPath} -D -f ${sshdDirectory}/sshd_config
      '';
      executable = pkgs.writeShellScript "sshd-start-script" script;
    in
    "${executable}";
}
