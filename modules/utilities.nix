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
    binwalk
    #autopsy
    imhex
    powershell
    blueman
    pavucontrol
    go
    virt-manager
    yazi
    ];
}

