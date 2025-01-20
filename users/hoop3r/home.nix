{ pkgs, lib, ... }:
{
  home.username = "hoop3r";
  home.homeDirectory = "/home/hoop3r";

  programs.git = {
    userName = "hoop3r";
    userEmail = "nhoop2107@gmail.com";
  };

}
