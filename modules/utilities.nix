{ pkgs, lib, config, ... }:
with lib;
let cfg = config.modules.utilities;

in {
  options.modules.utilities = { enable = mkEnableOption "utilities"; };
  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      tmux
      unzip
      ripgrep
      fd
      fzf
      bat
      htop
      neovim
      fastfetch
      compose2nix
      nettools
    ];
  }
}