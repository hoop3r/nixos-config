{ config, pkgs, lib, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
      ./forensics.nix
      ./wireguard.nix
      ./tailscale.nix
    ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.grub.enable = false;

  # X1 Yoga Gen 6: GuC/HuC firmware improves Intel Xe GPU power management
  boot.kernelParams = [ "i915.enable_guc=3" ];

  networking = {
    networkmanager.enable = true;
    networkmanager.unmanaged = [ "type:802-11-wireless" ];
    hostName = "hoophq";

    # The AT&T BGW320-500's DNS proxy at 192.168.1.1 -- the only resolver the
    # DHCP lease hands out -- applies DNS rebinding protection: it strips
    # RFC1918 answers from upstream responses. plex.direct is a public wildcard
    # that deliberately resolves private addresses, so the filter silently
    # breaks it. Measured 2026-10-02, same query, three resolvers:
    #
    #   dig @192.168.1.1 192-168-1-209.<hash>.plex.direct -> NXDOMAIN
    #   dig @1.1.1.1     192-168-1-209.<hash>.plex.direct -> 192.168.1.209
    #   dig @8.8.8.8     192-168-1-209.<hash>.plex.direct -> 192.168.1.209
    #
    # Every private address this host advertises is affected -- 192.168.1.209,
    # 10.89.0.1, 10.89.1.1, 10.100.0.1 -- so a Plex client sitting on the same
    # LAN cannot resolve the server's own secure URL and falls back to the
    # plex.tv relay. PMS detects the filter and reports dnsRebindingProtection=1
    # when it publishes. The matching log line is:
    #   Network: 10-89-0-1.<hash>.plex.direct failed to resolve to 10.89.0.1
    #            but instead yielded (null)
    # 100.124.247.94 (tailnet) is unaffected: 100.64/10 is CGNAT space, not
    # RFC1918, and the BGW's filter does not cover it.
    #
    # `nameservers` is handed to openresolv as the `static` source at metric 1
    # (nixpkgs tasks/network-interfaces.nix:1856), which outranks any
    # DHCP-supplied entry. `networkmanager.dns = "none"` additionally stops NM
    # rewriting resolv.conf from the lease, so the file is deterministic rather
    # than merely ordered.
    #
    # Do NOT re-add 192.168.1.1 as a trailing fallback: glibc advances to the
    # next nameserver only on timeout, never on NXDOMAIN, so a rebind-filtered
    # NXDOMAIN from the first resolver would still be the final answer.
    #
    # Trade-off: *.attlocal.net (BGW-assigned local names) stops resolving.
    # Nothing on this box depends on it -- peers are reached by static IP, wg0
    # address, or tailnet name. Tailscale is unaffected either way; it runs
    # --accept-dns=false and MagicDNS is not writing resolv.conf here.
    nameservers = [
      "1.1.1.1"
      "1.0.0.1"
      "2606:4700:4700::1111"
      "2606:4700:4700::1001"
    ];
    networkmanager.dns = "none";
    firewall = {
      # NOTE: this list is duplicated verbatim by webserver.nix:485 in the
      # hoophq-services flake input, and the two are merged. Removing a port
      # HERE does not close it -- the other declaration still opens it on every
      # interface. That is why 22 is still reachable from the WAN despite the
      # interface-scoped rules in tailscale.nix and wireguard.nix.
      #
      # To actually close ssh to the WAN, drop 22 from BOTH lists, which means
      # a commit+push to the hoophq-services repo and a
      # `nix flake update hoophq-services`. Do it only after confirming ssh
      # works over wg0 AND tailscale0, and note that this box has a single NIC
      # serving as both LAN and WAN path -- so an interface-scoped DROP on
      # wlp0s20f3 would also kill ssh from the LAN. Source-scoped or nothing.
      allowedTCPPorts = [ 22 80 443 25565 ];
    };
  };

  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  # X1 Yoga Gen 6: prevent any suspend/hibernate path
  systemd.sleep.settings.Sleep = {
    AllowSuspend = false;
    AllowHibernation = false;
    AllowHybridSleep = false;
    AllowSuspendThenHibernate = false;
  };

  # X1 Yoga Gen 6: logind handles lid events independently of systemd-sleep
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
  };

  # X1 Yoga Gen 6: stay at full speed since this machine runs as a server
  powerManagement.cpuFreqGovernor = "performance";

  # X1 Yoga Gen 6: Intel thermal management daemon
  services.thermald.enable = true;

  # X1 Yoga Gen 6: firmware blobs for AX210 WiFi, Intel Xe GPU, BT
  hardware.enableRedistributableFirmware = true;

  users.groups.media = {
    gid = 990;
  };

  users.users.media = {
    uid = 990;
    isSystemUser = true;
    group = "media";
  };

  users.users.bugbyte = {
    isNormalUser = true;
    description = "Nicholas Hooper";
    extraGroups = [ "networkmanager" "wheel" "podman" "media" ];
    packages = with pkgs; [];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJzydk8Z5OxEqRfkip1b/i9qZLncsjaW+67s6NLH6u8h nhoop2107@gmail.com"
    ];
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  environment.systemPackages = with pkgs; [
     vim
     wget
     htop
     curl
     git
     clamav
     nettools
     dig
     lnav
     compose2nix
     podman-compose
     btop
     cloudflared
     wireguard-tools
  ];

  services.clamav.daemon.enable = true;
  services.clamav.updater.enable = true;

  services.journald = {
    storage = "persistent";
  };

  system.stateVersion = "26.05";

}
