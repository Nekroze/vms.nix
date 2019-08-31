{ config, lib, pkgs, ... }:

with lib;

{
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
                merge = loc: defs: (import <nixpkgs/lib/eval-config.nix> {
                  inherit system;
                  modules = let
                    extraConfig = {
                      boot.isVirtualMachine = true;
                        networking.hostName = mkDefault name;
                        networking.useDHCP = mkDefault false;
                      };
                    in [ extraConfig ] ++ (map (x: x.value) defs);
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

    unitTemplate = {
      description = "Virtual Machine '%i'";

      path = [ pkgs.qemu_kvm ];

      environment.INSTANCE = "%i";
      environment.root = "/var/lib/vms/%i/";

      preStart = ''
        mkdir -p "$root"
      '';

      script = "${pkgs.coreutils}/bin/true";
    };

    mkService = cfg: unitTemplate // {
      wantedBy = optional cfg.autoStart [ "machines.target" ];
      script = "${pkgs.coreutils}/bin/true";
    };
    mkNamedService = name: cfg: nameValuePair "vm@${name}" (mkService cfg);

  in mkIf (config.boot.enableVirtualMachines) {
    systemd.targets."multi-user".wants = [ "machines.target" ];

    systemd.services = listToAttrs (
      [{ name = "vm@"; value = unitTemplate; }]
      ++ mapAttrsToList mkNamedService config.virtualMachines);
  };
}
