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
        Whether this NixOS machine is a QEMU jirtual machine running
        in another NixOS system.
      '';
    };

    boot.enableVirtualMachines = mkOption {
      type = types.bool;
      default = !config.boot.isContainer;
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
      format = "qcow2";
    };
    mkBackingImagePath = cfg: "${mkBackingImage cfg}/nixos.qcow2";

    defaultService = {
      description = "Virtual Machine '%i'";
      path = [ pkgs.qemu_kvm ];
      restartIfChanged = mkDefault false;
      serviceConfig.ExecStart = "${pkgs.coreutils}/bin/true";
    };

    mkQemuCommand = cfg: let
      switches = cfg.qemuSwitches ++ [
        ''drive file=${cfg.rootImagePath},if=virtio,aio=threads,format=qcow2''
      ];
      options = map (v: "-${v}") switches;
    in concatStringsSep " " ([ qemu ] ++ options);

    mkService = cfg: let
      backingFile = mkBackingImagePath cfg;
    in defaultService // {
      enable = cfg.autoStart;
      wantedBy = optional cfg.autoStart "machines.target";

      preStart = ''
        mkdir -p "$(dirname ${cfg.rootImagePath})"
        [ -f "$root" ] || qemu-img create -f qcow2 -F qcow2 -b ${backingFile} "${cfg.rootImagePath}" "${toString cfg.rootImageSize}M"
        qemu-img rebase -f qcow2 -b ${backingFile} "${cfg.rootImagePath}"
      '';
      serviceConfig.ExecStart = mkQemuCommand cfg;

      # TODO: Remove the rest to prevent unwanted restarts during nixos-rebuild while VM's are in use
      restartTriggers = [ backingFile ];
      restartIfChanged = true;
    };
    mkNamedService = name: cfg: nameValuePair "vm@${name}" (mkService cfg);

  in mkIf (config.boot.enableVirtualMachines) {
    systemd.targets."multi-user".wants = [ "machines.target" ];

    systemd.services = listToAttrs (
      [{ name = "vm@"; value = defaultService; }]
      ++ mapAttrsToList mkNamedService config.virtualMachines);
  };
}
