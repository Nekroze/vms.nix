{ config, lib, pkgs, ... }:

with lib;
with import <nixpkgs/nixos/lib/qemu-flags.nix> { inherit pkgs; };

let
  system = config.nixpkgs.localSystem.system;
  qemu = qemuBinary pkgs.qemu;
  vmOptions = import ./vm-options.nix { inherit lib system; };
in {

  options = {

    boot.isVirtualMachine = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether this NixOS machine is a QEMU virtual machine running
        in another NixOS system.
      '';
    };

    boot.enableVirtualMachines = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to enable support for NixOS virtual machines.
      '';
    };

    virtualMachines = mkOption {
      type = types.attrsOf (types.submodule vmOptions);
      default = {};
      example = literalExample
        ''
          { database =
              { config =
                  { config, pkgs, ... }:
                  { services.postgresql.enable = true;
                    system.stateVersion = "19.03";
                  };
              };
          }
        '';
      description = ''
        A set of NixOS system configurations to be run as virtual
        machine. Each VM appears as a service
        <literal>vm-<replaceable>name</replaceable></literal>
        on the host system, allowing it to be started and stopped via
        <command>systemctl</command>.
      '';
    };

  };

  config = let

    mkBackingImage = cfg: import <nixpkgs/nixos/lib/make-disk-image.nix> {
      inherit lib pkgs;
      config = cfg.config;
      diskSize = cfg.baseImageSize;
      format = cfg.baseImageFormat;
    };
    mkBackingImagePath = cfg: "${mkBackingImage cfg}/nixos.${cfg.baseImageFormat}";

    defaultService = {
      description = "Virtual Machine '%i'";
      path = [ pkgs.qemu_kvm ];
      restartIfChanged = mkDefault false;
      serviceConfig.ExecStart = "${pkgs.coreutils}/bin/true";
    };

    mkQemuCommand = cfg: let
      switches = cfg.qemuSwitches ++ [
        ''drive file=${cfg.rootImagePath},if=virtio,aio=threads,format=${cfg.rootImageFormat}''
      ];
      options = map (v: "-${v}") switches;
    in concatStringsSep " " ([ qemu ] ++ options);

    mkService = cfg: defaultService // {
      enable = cfg.autoStart;
      wantedBy = optional cfg.autoStart "machines.target";

      preStart = let
        backingFile = mkBackingImagePath cfg;
        # TODO: See if rebase can be made smarter and only do it when neccesary
        imgOpts = [
          "-f ${cfg.rootImageFormat}" "-F ${cfg.baseImageFormat}" "-b ${backingFile}"
        ];
        imgCreateArgs = [ "${cfg.rootImagePath}" "${toString cfg.rootImageSize}M" ];
        imgRebaseArgs = [ "${cfg.rootImagePath}" ];
      in ''
        if [ ! -f "$root" ]; then
          mkdir -p "$(dirname ${cfg.rootImagePath})"
          qemu-img create ${concatStringsSep " " (imgOpts ++ imgCreateArgs)}
        else
          qemu-img rebase ${concatStringsSep " " (imgOpts ++ imgRebaseArgs)}
        fi
      '';
      serviceConfig.ExecStart = mkQemuCommand cfg;
    };
    mkNamedService = name: cfg: nameValuePair "vm@${name}" (mkService cfg);

  in mkIf (config.boot.enableVirtualMachines) {
    systemd.targets."multi-user".wants = [ "machines.target" ];

    systemd.services = listToAttrs (
      [{ name = "vm@"; value = defaultService; }]
      ++ mapAttrsToList mkNamedService config.virtualMachines);
  };
}
