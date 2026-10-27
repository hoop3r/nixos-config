{ pkgs, ... }:

{
  services.xserver.enable = true;
  services.xserver.desktopManager.xfce.enable = true;
  services.xserver.displayManager.startx.enable = true;

  environment.systemPackages = with pkgs; [
    autopsy
    sleuthkit
    testdisk
    libewf
  ];

  systemd.tmpfiles.rules = [
    "d /usr/local     0755 root root -"
    "d /usr/local/bin 0755 root root -"
    "L+ /usr/local/bin/perl - - - - ${pkgs.perl}/bin/perl"
  ];
}
