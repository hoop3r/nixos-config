{ ... }:
{
  specialisation.gnome = {
    inheritParentConfig = true;
    configuration = {
      services.xserver.desktopManager.gnome.enable = true;
      programs.hyprland.enable = false;
    };

  };

}