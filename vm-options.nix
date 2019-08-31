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

    rootImageFormat = mkOption {
      type = types.enum ["qcow2" "raw"];
      default = "qcow2";
      description = ''
        The format of the root image.
      '';
    };

    baseImageSize = mkOption {
      type = types.int;
      default = 10 * 1024;
      description = ''
        The size of the base image in MiB.
      '';
    };

    baseImageFormat = mkOption {
      type = types.enum ["qcow2" "raw"];
      default = "qcow2";
      description = ''
        The format of the base image.
      '';
    };

    memory = mkOption {
      type = types.int;
      default = 512;
      description = ''
        Size in MiB of memory to assign this virtual machine
      '';
    };

    qemuSwitches = mkOption {
      type = types.listOf types.str;
      default = [];
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

    cpu = mkOption {
      type = types.str;
      default = "host";
      description = ''
        The CPU model to emulate.
      '';
    };

    cores = mkOption {
      type = types.int;
      default = 1;
      description = ''
        The number of CPU cores this virtual machine has access to.
      '';
    };

    kvm = mkEnableOption "Kernal Virtual Machine acceleration";
    virtioRNG = mkEnableOption "Virtio accelerated Random Number Generator";
    memoryBalloon = mkEnableOption "Virtio memory ballooning";
  };

  config = mkIf options.config.isDefined {
    qemuSwitches = with config; [
      "nographic"
      "vga none"
      "m ${toString memory}"
      "cpu ${cpu}"
      "smp ${toString cores}"
    ]
    ++ optional kvm "enable-kvm"
    ++ optional memoryBalloon "device virtio-balloon,automatic=true"
    ++ optional virtioRNG "device virtio-rng-pci";
  };
}
