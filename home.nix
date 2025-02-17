{ lib, pkgs, inputs, callPackage, config, ... }:
{
  nixpkgs.config.allowUnfree = true;


  # xdg.configFile = {
  #   "zsh" = {
  #     # source = config.lib.file.mkOutOfStoreSymlink "${home.inputs.homeDirectory}/.config/zsh";
  #     source = config.lib.file.mkOutOfStoreSymlink "~/.zshrc";

  #     recursive = true;

  #   };
  # };
  

  home = {

    username = "hoop3r";
    homeDirectory = "/home/hoop3r";

    stateVersion = "24.11";

  };

  imports = [ 
    ./modules/utilities.nix
    ./modules/programs.nix
    ./modules/git.nix
    ./modules/hyprland.nix 
    ./modules/vscode.nix
  ];
}

