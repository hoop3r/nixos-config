{ pkgs, lib, config, ... }:

with lib;
let cfg = config.modules.utilities;

in {
  options.modules.utilities = { enable = mkEnableOption "utilities"; };
  config = mkIf cfg.enable {

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
    ];

  }
}
