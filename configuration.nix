
{ config, pkgs, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
    ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "nixbox";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  networking.networkmanager.enable = true;

  networking.openvpn = {
  enable = true;
  clientConfigs = [
      {
        name = "homevpn";
        configFile = "~/HomeLab/vpn-config/OpenVPN-Config.ovpn";
      }
    ];
  };

  time.timeZone = "America/New_York";

  services.xserver.enable = true;

  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;
  services.xserver.displayManager.gdm.wayland = true;

  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  services.printing.enable = true;

  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;

  };

  users.users.hoop3r = {
    isNormalUser = true;
    description = "Nicholas Hooper";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [
    ];
  };

  programs.steam = {
  enable = true;
  remotePlay.openFirewall = true;
  dedicatedServer.openFirewall = true; 
  localNetworkGameTransfers.openFirewall = true; 
  };
  
  environment.systemPackages = with pkgs; [
    home-manager
    git    
    wget
    nano
  ];


  system.stateVersion = "24.11";

}
