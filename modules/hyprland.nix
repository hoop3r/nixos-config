{ pkgs, ... }:
{
  home.packages = with pkgs; [
    hyprland
    fish
    waybar
    dunst
    wofi
    wl-clipboard
  ];

}
