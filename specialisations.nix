{ pkgs, ... }:
{
  specialisation.hyprland = {
    inheritParentConfig = true;
    configuration = {
      services.xserver.desktopManager.gnome.enable = false;
      programs.hyprland.enable = true;
      programs.hyprland.xwayland.enable = true;
      hardware.bluetooth.enable = true;
      hardware.bluetooth.powerOnBoot = true;
    };
  };
  specialisation.gnome = {
    inheritParentConfig =true;
    configuration = {
      services.xserver.desktopManager.gnome.enable = true;
      programs.hyprland.enable = false;
    };

  };
}

