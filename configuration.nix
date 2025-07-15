
{lib, config, pkgs, ... }:

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
    extraGroups = [ "networkmanager" "wheel" "docker" "libvirtd" "dialout" "wireshark"];
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
  
  environment.systemPackages = with pkgs; [
    home-manager
    git    
    wget
    nano
    openvpn
    docker
    protonup
    gparted
    hyprland
  ];
  
  environment.sessionVariables = {
    
    NIXOS_OZONE_WL = "1";
    STEAM_EXTRA_COMPAT_TOOLS_PATHS =
      "\${HOME}/.steam/root/compatibilitytools.d";
    FLAKE = "/home/.config/nixos-config";

  };

  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = true;
      swtpm.enable = true;
      ovmf = {
        enable = true;
        packages = [ pkgs.OVMFFull.fd ];
      };
    };
  };

  security.pam.services.hyprlock = {};

  services.thermald.enable = lib.mkDefault true;
  services.fprintd.enable = true;
  system.stateVersion = "25.05";

}
