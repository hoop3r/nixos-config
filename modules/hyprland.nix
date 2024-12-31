{ pkgs, ... }:
{
  home.packages = with pkgs; [
    hyprland
    fish
    waybar
    dunsts
    wofi
    wl-clipboard
  ];

}
