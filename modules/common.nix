{ pkgs, ... }:
{
  home.packages = with pkgs; [
    unzip
    ripgrep
    fd
    neovim
    fastfetch
  ];

  home.sessionVariables = {
    EDITOR = "nvim";
    TERMINAL = "alacritty";
  };

}
