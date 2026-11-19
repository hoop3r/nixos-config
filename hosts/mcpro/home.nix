{
  pkgs,
  config,
  ...
}:
{
  imports = [
    ./modules/zsh.nix
    ./modules/iterm2.nix
  ];

  home.username = "hoop3r";
  home.homeDirectory = "/Users/hoop3r";
  home.stateVersion = "25.11";

  home.sessionVariables = {
    FLAKE = "${config.home.homeDirectory}/nixos-config";
  };

  xdg.enable = true;

  programs.git = {
    enable = true;
    settings.user.name = "hoop3r";
    settings.user.email = "nhoop2107@gmail.com";
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  home.packages = with pkgs; [
    python3
    python3Packages.pip
    tmux
    unzip
    ripgrep
    fd
    htop
    neovim
    fastfetch
    btop
    yazi
    jq
    go
    nixd
    nixfmt
    wireshark
    postman
    utm
  ];
}
