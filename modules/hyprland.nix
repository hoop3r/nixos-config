{ pkgs, ... }:
{
  home.packages = with pkgs; [
    hyprland
    rofi
    hyprcursor
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
