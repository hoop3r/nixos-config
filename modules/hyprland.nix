{ pkgs, ... }:

{

  specialisation.hyprland = {
    inheritParentConfig = true;
    configuration = {
      services.xserver.desktopManager.gnome.enable = false;
      programs.hyprland.enable = true;
      programs.hyprland.xwayland.enable = true;
        environment.systemPackages = with pkgs; [
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
          nerd-fonts.jetbrains-mono
          font-awesome
          hyprshot
          playerctl
          brightnessctl
          wl-clipboard
          asciiquarium
          lavat
        ];
    };   

  };

}




