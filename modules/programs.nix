{ pkgs , inputs, ... }:
{
  programs = {

    firefox = {
      enable = true;
      profiles.hoop3r = {

        extensions = with inputs.firefox-addons.packages."x86_64-linux"; [
          ublock-origin
        ];

        bookmarks = [
          {
            name = "github";
            url = "https://github.com/";
          }
          {
            name = "notion";
            url = "https://www.notion.so";
          }
          {
            name = "calendar";
            url = "https://calendar.notion.so/";
          }
          {
            name = "mail";
            url = "https://outlook.office365.com/mail/";
          }
          {
            name = "blog";
            url = "https://hoop3r.com/";
          }
        ];
      };
    };

    zsh = {
      enable = true;
      autosuggestions.enable = true;
      syntaxHighlighting.enable = true;
      ohMyZsh = {
        enable = true;
        plugins = [ "git" "docker" ];
      }
    };

  };

  home.packages = with pkgs; [
    teams-for-linux
    discord
    prismlauncher
    steam
    gimp
    cider
    wireshark
    drawio
    slack
  ];

}
