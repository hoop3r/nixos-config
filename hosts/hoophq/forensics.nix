{ pkgs, ... }:

{
  services.xserver.enable = true;
  services.xserver.desktopManager.xfce.enable = true;
  services.xserver.displayManager.startx.enable = true;

  # Autopsy runs here and is displayed on the client over `ssh -Y`. Enabling
  # X11Forwarding also makes NixOS install xauth for sshd.
  services.openssh.settings.X11Forwarding = true;

  environment.systemPackages = with pkgs; [
    # nixpkgs' own autopsy: x86_64-only upstream, which is exactly this host.
    # Unlike the aarch64-darwin build, 7-Zip and OpenCV work here, so archive
    # recursion and Object Detection are available.
    autopsy

    sleuthkit # fls, mmls, icat, tsk_recover, mactime, ...
    testdisk  # photorec, used by the PhotoRec Carver ingest module
    libewf    # ewfacquire / ewfverify for E01
  ];

  systemd.tmpfiles.rules = [
    "d /usr/local     0755 root root -"
    "d /usr/local/bin 0755 root root -"
    "L+ /usr/local/bin/perl - - - - ${pkgs.perl}/bin/perl"
  ];
}
