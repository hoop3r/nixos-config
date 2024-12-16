{ pkgs , ... }:
{
  programs = {

    vscode = {
      enable = true;
      extensions = [];
    };
  };

  home.packages = with pkgs; [
    teams-for-linux
    discord
    steam
  ];
}
