{ pkgs, ... }:
{
  home.packages = with pkgs; [
    hyprland
    rofi
    waybar
    dunst
    kitty
    swaybg
    swaylock-fancy
    swayidle
    pamixer
    light
    brillo
    nerdfonts
  ];

}
