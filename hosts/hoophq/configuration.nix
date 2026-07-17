{ config, pkgs, lib, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
    ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.grub.enable = false;

  # X1 Yoga Gen 6: GuC/HuC firmware improves Intel Xe GPU power management
  boot.kernelParams = [ "i915.enable_guc=3" ];

  networking = {
    networkmanager.enable = true;
    networkmanager.unmanaged = [ "type:802-11-wireless" ];
    hostName = "hoophq";
    firewall = {
      allowedTCPPorts = [ 22 80 443 25565 ];
    };
  };

  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  # X1 Yoga Gen 6: prevent any suspend/hibernate path
  systemd.sleep.settings.Sleep = {
    AllowSuspend = false;
    AllowHibernation = false;
    AllowHybridSleep = false;
    AllowSuspendThenHibernate = false;
  };

  # X1 Yoga Gen 6: logind handles lid events independently of systemd-sleep
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
  };

  # X1 Yoga Gen 6: stay at full speed since this machine runs as a server
  powerManagement.cpuFreqGovernor = "performance";

  # X1 Yoga Gen 6: Intel thermal management daemon
  services.thermald.enable = true;

  # X1 Yoga Gen 6: firmware blobs for AX210 WiFi, Intel Xe GPU, BT
  hardware.enableRedistributableFirmware = true;

  users.groups.media = {
    gid = 990;
  };

  users.users.media = {
    uid = 990;
    isSystemUser = true;
    group = "media";
  };

  users.users.bugbyte = {
    isNormalUser = true;
    description = "Nicholas Hooper";
    extraGroups = [ "networkmanager" "wheel" "podman" "media" ];
    packages = with pkgs; [];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJzydk8Z5OxEqRfkip1b/i9qZLncsjaW+67s6NLH6u8h nhoop2107@gmail.com"
    ];
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  environment.systemPackages = with pkgs; [
     vim
     wget
     htop
     curl
     git
     clamav
     nettools
     dig
     lnav
     compose2nix
     podman-compose
     btop
     cloudflared
  ];

  services.clamav.daemon.enable = true;
  services.clamav.updater.enable = true;

  services.journald = {
    storage = "persistent";
  };

  system.stateVersion = "26.05";

}
