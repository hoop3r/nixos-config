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

  programs.steam = {
  enable = true;
  remotePlay.openFirewall = true;
  dedicatedServer.openFirewall = true; 
  localNetworkGameTransfers.openFirewall = true; 
  };

}
