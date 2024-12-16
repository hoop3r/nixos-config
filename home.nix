{ lib, pkgs, ... }:
{
  nixpkgs.config.allowUnfree = true;

  home = {

    username = "hoop3r";
    homeDirectory = "/home/hoop3r";

    stateVersion = "24.11";

  };

  imports = [ 
    ./modules/common.nix
    ./modules/programs.nix
    ./modules/git.nix
    ./modules/hyprland.nix 
  ];
}

