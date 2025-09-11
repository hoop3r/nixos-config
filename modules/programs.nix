{ pkgs , inputs, ... }:
{
  programs = {
  
    firefox = {
      enable = true;
      profiles.hoop3r = {
        extensions.packages = with inputs.firefox-addons.packages."x86_64-linux"; [
          ublock-origin
        ];
      };
    };

    zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
    };
  };

  home.packages = with pkgs; [
    teams-for-linux
    discord
    prismlauncher
    steam
    gimp
    drawio
    slack
    wireshark
    ghidra
    burpsuite
    plex-desktop
  ];

}

