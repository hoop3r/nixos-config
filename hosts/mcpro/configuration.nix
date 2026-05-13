{ pkgs, ... }:
{
  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.config.allowUnfree = true;

  networking.hostName = "mcpro";

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nix.optimise.automatic = true;

  users.users.hoop3r = {
    name = "hoop3r";
    home = "/Users/hoop3r";
    shell = pkgs.zsh;
  };

  environment.systemPath = [
    "/run/current-system/sw/bin"
    "/nix/var/nix/profiles/default/bin"
  ];

  programs.zsh.enable = true;

  environment.systemPackages = with pkgs; [
    git
    wget
    vim
    home-manager
  ];

  system.stateVersion = 6;
}
