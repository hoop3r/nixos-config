{ pkgs, config, ... }:
{
  users.users.hoop3r = {
    isNormalUser = true;
    description = "Nicholas Hooper";
    extraGroups = [ "networkmanager" "wheel" ];
  };
}