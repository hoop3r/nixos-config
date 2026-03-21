
{lib, config, pkgs, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
    ];
    
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  
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
  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;
  services.desktopManager.plasma6.enable = true;

#  services.xserver.displayManager.gdm.enable = true;
#  services.xserver.desktopManager.gnome.enable = true;

  xdg.portal.enable = true;
  xdg.portal.xdgOpenUsePortal = true;
  xdg.portal.extraPortals = [
    pkgs.xdg-desktop-portal-gnome
    pkgs.xdg-desktop-portal-gtk
  ];
  
  services.printing.enable = true;

  services.pulseaudio.enable = false;
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
    extraGroups = [ "networkmanager" "wheel" "docker" "libvirt" "dialout" "wireshark"];
    shell = pkgs.zsh;
  };
  
  programs.zsh.enable = true;

  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true; 
    localNetworkGameTransfers.openFirewall = true; 
  };

  programs.nix-ld.enable = true;

  virtualisation.docker.enable = true;
  virtualisation.libvirtd.enable = true;
  virtualisation.libvirtd.package = pkgs.libvirt;
  virtualisation.virtualbox.host.enable = true;
  users.extraGroups.vboxusers.members = [ "hoop3r" ];
  
  environment.systemPackages = with pkgs; [
    home-manager
    git    
    wget
    nano
    openvpn
    docker
    protonup-ng
    gparted
    hyprland
    clamav
  ];
  
  environment.sessionVariables = {
    
    NIXOS_OZONE_WL = "1";
    STEAM_EXTRA_COMPAT_TOOLS_PATHS =
      "\${HOME}/.steam/root/compatibilitytools.d";
    FLAKE = "/home/hoop3r/nixos-config";

  };

  virtualisation.virtualbox.host.enableExtensionPack = true;

  security.pam.services.hyprlock = {};

  services.clamav.daemon.enable = true;
  services.clamav.updater.enable = true;

  services.thermald.enable = lib.mkDefault true;
  services.fprintd.enable = true;
  system.stateVersion = "25.11";


}
