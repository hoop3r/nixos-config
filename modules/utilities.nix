{ pkgs, ... }:
{
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
    pdfstudio2024
  ];
}
