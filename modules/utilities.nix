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
  ];
}
