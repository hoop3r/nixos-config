{ ... }:
{
  programs.git.enable = true;
  programs.home-manager.enable = true;
  home.sessionVariables.NIXPKGS_ALLOW_UNFREE = "1";

  imports = [
    ./hyprland.nix
    ./programs.nix
    ./utilities.nix
  ];
}