{ config, lib, pkgs, ... }:

with lib;
with import <nixpkgs/nixos/lib/qemu-flags.nix> { inherit pkgs; };

let
  system = config.nixpkgs.localSystem.system;
  qemu = qemuBinary pkgs.qemu;
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
      type = types.attrsOf (types.submodule (
        { config, options, name, ... }:
        {
          options = {

            config = mkOption {
              description = ''
                A specification of the desired configuration of this
                virtual machine, as a NixOS module.
              '';
              type = lib.mkOptionType {
                name = "Toplevel NixOS config";
                merge = loc: defs: (import <nixpkgs/nixos/lib/eval-config.nix> {
                  inherit system;
                  modules = [
                    rec {

                      imports = [
                        ./default.nix
                        <nixpkgs/nixos/modules/profiles/qemu-guest.nix>
                        <nixpkgs/nixos/modules/profiles/headless.nix>
                      ];
                      boot.isVirtualMachine = true;
                      networking.hostName = mkDefault name;
                      networking.useDHCP = mkDefault false;
                      fileSystems."/" = {
                        device = "/dev/disk/by-label/nixos";
                        autoResize = true;
                        fsType = "ext4";
                      };
                      boot.growPartition = true;
                      boot.loader.grub.device = "/dev/sda";
                      boot.kernelParams = [ "console=${qemuSerialDevice}" ];

                    } ] ++ (map (x: x.value) defs);
                  prefix = [ "virtualMachines" name ];
                }).config;
              };
            };

            path = mkOption {
              type = types.path;
              example = "/nix/var/nix/profiles/vms/webserver";
              description = ''
                As an alternative to specifying
                <option>config</option>, you can specify the path to
                the evaluated NixOS system configuration, typically a
                symlink to a system profile.
              '';
            };

            rootImagePath = mkOption {
              type = types.str;
              default = "/var/lib/vms/${name}.qcow2";
              description = ''
                Path to store the root image.
              '';
            };

            rootImageSize = mkOption {
              type = types.int;
              default = 10 * 1024;
              description = ''
                The size of the root image in MiB.
              '';
            };

            baseImageSize = mkOption {
              type = types.int;
              default = 10 * 1024;
              description = ''
                The size of the base image in MiB.
              '';
            };

            qemuSwitches = mkOption {
              type = types.listOf types.str;
              default = [
                "nographic" "enable-kvm"
                "device virtio-rng-pci"
                "device vhost-vsock-pci,id=vhost-vsock-pci0,guest-cid=3"
                "cpu host"
                "smp sockets=1,cpus=4,cores=2"
                "m 1024"
                "vga none"
              ];
              description = ''
                Switches given to QEMU cli when starting this virtual machine.
                All switches will have - prepended automatically.
              '';
            };

            autoStart = mkOption {
              type = types.bool;
              default = false;
              description = ''
                Whether the virtual machine is automatically started at boot-time.
              '';
            };

          };

          config = mkIf options.config.isDefined {
            path = config.config.system.build.toplevel;
          };
        }));

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
