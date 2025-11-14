{ pkgs, ... }:
{
  specialisation.hyprland = {
    inheritParentConfig = true;
    configuration = {
      services.desktopManager.gnome.enable = false;
      services.desktopManager.plasma6.enable = false;
      programs.hyprland.enable = true;
      programs.hyprland.withUWSM = true;
      programs.hyprland.xwayland.enable = true;
      # hardware.bluetooth.enable = true;
      # hardware.bluetooth.powerOnBoot = true;
    };
  };
  specialisation.gnome = {
    inheritParentConfig = true;
    configuration = {
      services.xserver.displayManager.gdm.enable = true;
      desktopManager.gnome.enable = true;
      programs.hyprland.enable = false;
    
      services.desktopManager.plasma6.enable = false;
    };

  };
  specialisation.kde = {
    inheritParentConfig = true;
    configuration = {
      services.xserver.displayManager.gdm.enable = pkgs.lib.mkForce false;
      services.xserver.displayManager.sddm.enable = pkgs.lib.mkForce true;
      programs.hyprland.enable = false;
      services.xserver.desktopManager.gnome.enable = false;
      services.xserver.desktopManager.plasma6.enable = true;
      services.xserver.displayManager.defaultSession = "plasma";
    };
  };
}

