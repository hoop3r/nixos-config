{ pkgs, ... }:
{
  home.packages = with pkgs; [
    alacritty
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
