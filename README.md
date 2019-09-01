# vms.nix

A [NixOS][1] module that provides [QEMU][2] based virtual machines using a similar
configuration interface to the `containers` [NixOS][1] options.

## Usage

Before proceeding you must first import this module. Simply clone this
repository and place it under `/etc/nixos/` then in your
`/etc/nixos/configuration.nix` add the following imports:

```nix
{
  imports = [
    ./vms.nix
  ];
}
```

### Enabling

Everything this module does can be enabled or disabled with the
`boot.enableVirtualMachines`, so the first step is to set that to true
somewhere in your [NixOS][1] configuration.

```nix
{
  boot.enableVirtualMachines = true;
}
```

If we later set this option to `false` all virtual machines will be stopped and
their services removed, although any data will persist.

### First Virtual Machine

Let's test the waters by starting a dead simple VM that we can remotely connect to:

```nix
{
  boot.enableVirtualMachines = true;

  virtualMachines.guest = {
    autoStart = true;

    config = {
      system.stateVersion = "19.03";
      services.openssh.enable = true;
      users.users.root.openssh.authorizedKeys.keyFiles = [
        /root/.ssh/authorized_keys
      ];
    };

    qemuSwitches = [
      "nic user,hostfwd=tcp::10022-:22"
    ];
  };
}
```

Here we have defined a virtual machine called `guest` that runs `openssh`,
allowing in to root anyone that has been given remote access to the root user
of the [NixOS][1] host machine via the `/root/.ssh/authorized_keys` files.

Finally we add an extra switch to [QEMU][2] to be used when the VM starts that
sets up network forwarding from `localhost:10022` on the host machine to port
`22` in the guest machine.

Now we can run `nixos-rebuild switch` and the VM will come online ready for
connection. First we will check the VM service's status where we should be able
to see the boot log.

```bash
systemctl status vm@guest
```

All `virtualMachines` are managed via a systemd service named `vm@$VM_NAME`. We
can also stop, start, or restart this service.

Before a machine starts (other than its first time) it will attempt to migrate
the backing store of the disk image, this means that the config is deployed
onto a disk image in your `/nix/store` but any changes to the VM once it is
running are stored on the root disk image at
`/var/lib/vms/$VM_NAME.$VM_ROOT_IMAGE_FORMAT` so if we wanted to erase any
state that has built up for the `guest` VM I can delete
`/var/lib/vms/guest.qcow2`. This path can be changed via the
`virtualMachines.guest.rootImagePath` option.

Let's get on with it and get in there, assuming you have a key in
`/root/.ssh/authorized_keys`:

```bash
ssh -p 10022 root@localhost
```

[1]: https://nixos.org/nixos
[2]: https://www.qemu.org/
[3]: https://nixos.org/nix
