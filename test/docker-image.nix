{ system ? builtins.currentSystem
, pkgs ? import <nixpkgs> { inherit system; }
, output ? "image"
}:

let
  nixos = import <nixpkgs/nixos> {
    inherit system;
    configuration = {
      nixpkgs.pkgs = pkgs;

      imports = [
        <nixpkgs/nixos/modules/virtualisation/disk-image.nix>
        <nixpkgs/nixos/modules/virtualisation/qemu-vm.nix>
      ];

      # disk-image.nix turns system.build.image into a bootable qcow2 image.
      image.format = "qcow2";
      image.efiSupport = false;

      boot.loader.grub.device = "/dev/vda";
      boot.loader.timeout = 0;
      boot.kernelParams = [
        "console=ttyS0,115200n8"
        "console=tty0"
      ];
      boot.kernelModules = [
        "br_netfilter"
        "fuse"
        "overlay"
      ];
      boot.kernel.sysctl = {
        "net.ipv4.ip_forward" = 1;
        "net.ipv6.conf.all.forwarding" = 1;
      };

      # Use Docker as the guest engine. Podman is deliberately not enabled
      # or installed here; the Podman binary under test lives in the image
      # pulled by the test script.
      virtualisation.docker = {
        enable = true;
        enableOnBoot = true;
        storageDriver = "overlay2";
      };
      virtualisation.mountHostNixStore = false;
      virtualisation.useNixStoreImage = false;

      environment.systemPackages = with pkgs; [
        bash
        coreutils
        curl
        docker
        docker-compose
        git
        iproute2
        jq
        openssh
        qemu-utils
        sshpass
      ];

      services.openssh = {
        enable = true;
        settings = {
          PermitRootLogin = "yes";
          PasswordAuthentication = true;
        };
      };

      users.mutableUsers = false;
      users.users.root.initialHashedPassword = "$6$tEI3gQs0Btzt1Chd$se4yg0TbtA7DeNXG.H19YOVHTkc.4INnG5xpn4QX/EmH536zpQBbrR/Wp.BkzgnQdDF3OUvNl.rg7bMO.faLq1";

      networking.firewall.enable = false;
      # Keep the standalone runner usable on hosts where virtiofsd cannot
      # retain capabilities. The disk image already contains the Nix store.
      virtualisation.sharedDirectories = pkgs.lib.mkForce { };
      virtualisation.graphics = false;
      virtualisation.memorySize = 4096;
      virtualisation.cores = 4;
      virtualisation.diskSize = 32768;

      system.stateVersion = "25.05";
    };
  };
  outputs = {
    image = nixos.config.system.build.image;
    kernel = nixos.config.system.build.kernel;
    initrd = nixos.config.system.build.initialRamdisk;
    toplevel = nixos.config.system.build.toplevel;
    vm = nixos.config.system.build.vm;
    kernelParams = pkgs.writeText "docker-image-kernel-params" (
      builtins.concatStringsSep " " nixos.config.boot.kernelParams
    );
  };
in
if output == "metadata" then outputs else outputs.image
