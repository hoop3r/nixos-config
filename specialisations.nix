{ pkgs, lib, inputs, ... }:
{
  specialisation.hyprland = {
    inheritParentConfig = true;
    configuration = {
      services.desktopManager.plasma6.enable = lib.mkForce false;
      services.displayManager.sddm.enable = lib.mkForce false;
      services.displayManager.sddm.wayland.enable = lib.mkForce false;

      programs.hyprland = {
        enable = true;
        package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
        portalPackage = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
        xwayland.enable = true;
      };

      services.greetd = {
        enable = true;
        settings.default_session = {
          command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --cmd Hyprland";
          user = "greeter";
        };
      };

      xdg.portal.extraPortals = lib.mkForce [
        inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland
        pkgs.xdg-desktop-portal-gtk
      ];
    };
  };
}
