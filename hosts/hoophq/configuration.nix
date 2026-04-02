{ config, pkgs, lib, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
    ];
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";
  boot.loader.grub.useOSProber = true;
  boot.blacklistedKernelModules = [ "iwlwifi" ];
  
  networking = {
    networkmanager.enable = true;
    networkmanager.unmanaged = [ "type:802-11-wireless" ];
    hostName = "hoophq";
    firewall = {
      allowedTCPPorts = [22 80 443 25565];
    };
  };

  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";
  
  systemd.timers."podman-auto-update" = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };

  services.podman.autoPrune = {
    enable = true;
    dates = "daily";
  };

  systemd.sleep.extraConfig = ''
    AllowSuspend=no
    AllowHibernation=no
    AllowHybridSleep=no
    AllowSuspendThenHibernate=no
  '';

  users.users.bugbyte = {
    isNormalUser = true;
    description = "Nicholas Hooper";
    extraGroups = [ "networkmanager" "wheel" "podman" ];
    packages = with pkgs; [];
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

  system.stateVersion = "25.11";

}
