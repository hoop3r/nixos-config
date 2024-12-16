{ pkgs, ... }:
{
  home.packages = with pkgs; [
    unzip
    ripgrep
    fd
    htop
    neovim
    fastfetch
  ];

  home.sessionVariables = {
    EDITOR = "nvim";
    TERMINAL = "kitty";
  };

}
