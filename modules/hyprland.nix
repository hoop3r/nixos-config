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
    hyprlock
    swayidle
    pamixer
    light
    brillo
    nerdfonts
    hyprshot
    playerctl
    brightnessctl
    wl-clipboard
    asciiquarium
    lavat
  ];

}

