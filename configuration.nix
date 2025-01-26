
{ config, pkgs, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
    ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "thinkpad";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  networking.networkmanager.enable = true;

  
  services.openvpn.servers = {
    officeVPN  = {
      config = '' config /home/hoop3r/Lab/HoopHQ/vpn-config/OpenVPN-Config.ovpn '';
      updateResolvConf = true;
    };
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
    extraGroups = [ "networkmanager" "wheel" "docker" ];
    packages = with pkgs; [
    ];
  };

  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true; 
    localNetworkGameTransfers.openFirewall = true; 
  };

  programs.nix-ld.enable = true;

  virtualisation.docker.enable = true;
  
  environment.systemPackages = with pkgs; [
    home-manager
    git    
    wget
    nano
    openvpn
    docker
    protonup
    nh
  ];
  
  environment.sessionVariables = {
    
    NIXOS_OZONE_WL = "1";
    STEAM_EXTRA_COMPAT_TOOLS_PATHS =
      "\${HOME}/.steam/root/compatibilitytools.d";
    FLAKE = "/home/.config/nixos-config";

  };
  
  system.stateVersion = "24.11";

}
