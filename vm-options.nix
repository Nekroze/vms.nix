# This is just the VM specific config and options being built
{ lib, system }:
{ config, options, name, ... }:

with lib;
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
          modules = [{
            networking.hostName = mkDefault name;
            imports = [ # Import the vm profile for all guests
              ./vm-profile.nix
            ];
          }] ++ (map (x: x.value) defs);
          prefix = [ "virtualMachines" name ];
        }).config;
      };
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
        "vga none"
        "device virtio-rng-pci"
        "cpu host"
        "smp sockets=1,cpus=1,cores=1"
        "m 512"
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
  };
}
