{ pkgs , ... }:
{

  programs = {

    zsh = {
      enable = true;
      #ohMyZsh.enable = true;
    };
    vscode = {
      enable = true;
      extensions = [];
    };
  };

  home.packages = with pkgs; [
    wireshark
    teams-for-linux
    discord
    steam
  ];
}
