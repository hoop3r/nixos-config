{ lib, pkgs, ... }:

{
  nixpkgs.config.allowUnfree = true;

  home.username      = "hoop3r";
  home.homeDirectory = "/home/hoop3r";
  home.stateVersion  = "24.11";

  home.file.".zshrc".source = ./dotfiles/.zshrc;

  xdg.enable = true; 

  xdg.configFile = {
    "hypr/hyprlock.conf" = {
      source = ./dotfiles/hyprlock.conf;
      force  = true;
    };
    "hypr/hyprland.conf" = {
      source = ./dotfiles/hyprland.conf;
      force  = true;
    };
    "hypr/keybindings.conf" = {
      source = ./dotfiles/hyprkeys.conf;
      force  = true;
    };
    "kitty/kitty.conf" = {
      source = ./dotfiles/kitty.conf;
      force  = true;
    };
  };

  imports = [
    ./modules/utilities.nix
    ./modules/programs.nix
    ./modules/git.nix
    ./modules/hyprland.nix
    ./modules/vscode.nix
  ];
}
