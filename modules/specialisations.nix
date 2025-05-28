{ pkgs, ... }:
{
  specialisation.hyprland = {
    inheritParentConfig = true;
    configuration = {
      services.xserver.desktopManager.gnome.enable = false;
      programs.hyprland.enable = true;
      programs.hyprland.xwayland.enable = true;
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

