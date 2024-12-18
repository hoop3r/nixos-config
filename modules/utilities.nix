{ pkgs, ... }:
{
  home.packages = with pkgs; [
    unzip
    ripgrep
    fd
    fzf
    bat
    htop
    neovim
    fastfetch
  ];
}
