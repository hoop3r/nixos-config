{ pkgs, ... }:
{
  home.packages = with pkgs; [
    kitty
    waybar
    dunst
    wofi
    hyprland
    wl-clipboard
  ];

 # xdg.portal = {
 #   enable = true;
 #   enablePipewire = true;
 # };
}
