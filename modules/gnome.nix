{ ... }:
{
  system.specialisation.hyprland = {
    inheritParentConfig = true;
    configuration = {
      services.xserver.displayManager.gdm.enable = true;
      services.xserver.displayManager.sddm.enable = false;
      services.xserver.desktopManager.gnome.enable = true;
      programs.hyprland.enable = false;
    };
    name = "gnome";
  };
}