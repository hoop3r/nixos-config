{ pkgs, ... }:
{
  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.config.allowUnfree = true;

  networking.hostName = "mcpro";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.optimise.automatic = true;

  environment.systemPackages = with pkgs; [
    git
    wget
    kitty
  ];

  system.stateVersion = 6;
}