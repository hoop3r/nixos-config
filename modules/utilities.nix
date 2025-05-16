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
    gcc
    icu
    docker-compose
    vagrant
    git-graph
    minicom
    clamav
    binwalk
    autopsy
    imhex
    powershell
    blueman
    pavucontrol
    ];
}

