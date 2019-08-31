{pkgs, lib, ...}:

with lib;
with import <nixpkgs/nixos/lib/qemu-flags.nix> { inherit pkgs; };

{
  imports = [
    ./default.nix
    <nixpkgs/nixos/modules/profiles/qemu-guest.nix>
    <nixpkgs/nixos/modules/profiles/headless.nix>
  ];
  boot.isVirtualMachine = true;
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    autoResize = true;
    fsType = "ext4";
  };

  boot.growPartition = true;
  boot.loader.grub.device = "/dev/sda";
  boot.kernelParams = [ "console=${qemuSerialDevice}" ];
}
