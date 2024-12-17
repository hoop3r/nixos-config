{ config, pkgs, lib, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
    ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "nixbox";
  networking.networkmanager.enable = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  time.timeZone = "America/New_York";

  services.xserver.enable = true;

  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;
  services.xserver.displayManager.gdm.wayland = true;

  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  services.printing.enable = true;

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

  specialisation = {
  
    hyprland.configuration = {
      system.nixos.tags = [ "hyprland" ];
      
      programs.hyprland.enable = true;
      services.xserver.desktopManager.gnome.enable = lib.mkForce false;

      environment.systemPackages = with pkgs; [
        hyprland
        kitty          
        waybar         
        rofi           
        dunst          
        swaylock       
        grim slurp     
      ];

      environment.variables = {
        WLR_NO_HARDWARE_CURSORS = "1";
        XDG_SESSION_TYPE = "wayland";
      };
    };

    gnome.configuration = {
      system.nixos.tags = [ "gnome" ];

      services.xserver.enable = true;
      services.xserver.displayManager.gdm.enable = true;
      services.xserver.desktopManager.gnome.enable = true;

      environment.systemPackages = with pkgs; [
        gnome.gnome-tweaks
        gnome.dconf-editor
        gnome.gnome-terminal
        gnome.nautilus
      ];

      programs.dconf.enable = true;
    };
  };

  system.stateVersion = "24.11";
}