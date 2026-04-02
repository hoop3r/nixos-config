{ pkgs, ... }:
{
  programs.git = {
    enable = true;
    settings.user.name = "hoop3r";
    settings.user.email = "nhoop2107@gmail.com";
  };
}