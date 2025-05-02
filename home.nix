{ lib, pkgs, inputs, callPackage, config, ... }:
{
  nixpkgs.config.allowUnfree = true;
  

  home = {

    username = "hoop3r";
    homeDirectory = "/home/hoop3r";

    stateVersion = "24.11";
    file = { 
      ".zshrc" = {
        source = ./dotfiles/zshrc;
      };
      ".config/hypr/hyprlock.conf" = {
        source = ./dotfiles/hyprlock.conf;
      };
      ".config/hypr/hyprland.conf" = {
        source = ./dotfiles/hyprland.conf;
      };
      ".config/hypr/keybindings.conf" = {
        source = ./dotfiles/hyprkeys.conf;
      };
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

