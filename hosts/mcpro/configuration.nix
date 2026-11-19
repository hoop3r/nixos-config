{ pkgs, ... }:
{
  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [ (import ../../pkgs/overlay.nix) ];

  networking.hostName = "mcpro";

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nix.optimise.automatic = true;

  users.users.hoop3r = {
    name = "hoop3r";
    home = "/Users/hoop3r";
    shell = pkgs.zsh;
  };

  environment.systemPath = [
    "/run/current-system/sw/bin"
    "/nix/var/nix/profiles/default/bin"
  ];

  # /etc/zshrc only needs to exist so login shells work; the interactive setup
  # (compinit, prompt, plugins) is owned by home-manager in modules/zsh.nix.
  programs.zsh = {
    enable = true;
    enableGlobalCompInit = false; # home-manager runs compinit itself
    promptInit = ""; # starship sets the prompt
  };

  environment.systemPackages = with pkgs; [
    git
    wget
    vim
    home-manager

    # Digital forensics. `autopsy` is the overlay's aarch64-darwin build; it
    # carries its own JDK and points at this same sleuthkit for the JNI bindings.
    autopsy
    sleuthkit # fls, mmls, icat, tsk_recover, mactime, ...
    testdisk
    libewf # ewfacquire/ewfverify for E01
  ];

  # Required by user-scoped options (system defaults, Touch ID sudo) in nix-darwin 26.05.
  system.primaryUser = "hoop3r";

  security.pam.services.sudo_local.touchIdAuth = true;
  system.stateVersion = 6;
}
