{ pkgs, ... }:
{
  home.packages = with pkgs; [
    hyprland
    kitty
    waybar
    dunst
    wofi
    wl-clipboard
  ];

}
