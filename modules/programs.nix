{ pkgs , ... }:
{
  programs = {

    vscode = {
      enable = true;
      extensions = [];
    };

    firefox = {
      enable = true;
      profiles.hoop3r = {

        extensions = with pkgs.firefox-addons; [
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
  };

  home.packages = with pkgs; [
    teams-for-linux
    discord
    steam
  ];

}
