{ config, pkgs, lib, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
      ./forensics.nix
      ./tailscale.nix
      ./pihole.nix
      ./homeassistant.nix
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
      # interface-scoped rule in tailscale.nix.
      #
      # To actually close ssh to the WAN, drop 22 from BOTH lists, which means
      # a commit+push to the hoophq-services repo and a
      # `nix flake update hoophq-services`. Do it only after confirming ssh
      # works over tailscale0, and note that this box has a single NIC
      # serving as both LAN and WAN path -- so an interface-scoped DROP on
      # wlp0s20f3 would also kill ssh from the LAN. Source-scoped or nothing.
      allowedTCPPorts = [ 22 80 443 25565 ];
    };
  };

  # Origin-side HTTP/2 off on every TLS vhost.
  #
  # nginx's `http2` is a property of the LISTENING SOCKET, not the server
  # block. All five of these share 0.0.0.0:443, so leaving it enabled on even
  # one re-enables it for all of them -- nixpkgs says so outright in
  # vhost-options.nix ("If there is one server block configured to enable
  # http2, then it is enabled for all server blocks on this IP"). Hence
  # genAttrs over the complete list: this is all-or-nothing by design.
  #
  # There is NO top-level services.nginx.http2 option -- it exists only
  # per-vhost -- and these vhosts are defined in the hoophq-services flake
  # input. So the attribute is merged in from here, exactly the way
  # tailscale.nix adds a webfinger location to hoop3r.com. That keeps the
  # change out of the submodule and avoids a commit+push plus a
  # `nix flake update hoophq-services` just to flip a boolean.
  #
  # Cloudflare needs no matching change: "HTTP/2 to Origin" is on by default,
  # but it ALPN-negotiates, so once nginx stops announcing h2 the edge falls
  # back to HTTP/1.1 by itself. Visitors are unaffected -- they negotiate with
  # the edge, and the firewall above means edge nodes are the only peers that
  # ever reach nginx.
  #
  # mc.hoop3r.com is absent on purpose: it has no SSL, and the directive is
  # gated on hasSSL, so no http2 line is emitted for it either way.
  services.nginx.virtualHosts = lib.genAttrs [
    "auth.hoop3r.com"
    "fieldofvisiondrone.com"
    "hoop3r.com"
    "howdyitsanna.com"
    "plex.hoop3r.com"
  ] (_: { http2 = false; });

  # Worker scaling -- partial mitigation for CVE-2026-118899 (fixed in nginx
  # 1.30.7, not yet in nixos-26.05; we run 1.30.6).
  #
  # That bug lets a worker get caught in an endless loop while reading a
  # request body over SSL. It needs only TLS + a body -- no HTTP/2, so the
  # http2 = false block above does NOT cover it, and Cloudflare proxies a
  # malicious POST straight through. nginx's default worker_processes is 1 and
  # NixOS does not override it, so a SINGLE looping request was enough to take
  # all five vhosts down until a restart.
  #
  # `auto` = one worker per core (8 here), so an attacker needs 8+ concurrent
  # loops instead of 1. Not a fix -- just removes the single point of failure.
  # Drop the worker_rlimit_nofile line and this comment's urgency once
  # nixos-26.05 ships >= 1.30.7; `auto` is worth keeping regardless, since 1
  # worker on an 8-core box was leaving most of the machine idle.
  #
  # prependConfig (not appendHttpConfig) because worker_processes is a MAIN
  # context directive -- appendHttpConfig lands inside http {} and would be a
  # config error there.
  #
  # worker_rlimit_nofile is required, not optional: the unit's soft NOFILE is
  # 1024, so worker_connections 2048 would otherwise just log "worker_connections
  # exceed open file resource limit: 1024" and cap. The hard limit is 524288,
  # so nginx can raise its own soft limit to 8192 unaided. Each proxied request
  # (plex, auth) burns two descriptors, hence the headroom over 2048.
  services.nginx.prependConfig = ''
    worker_processes auto;
    worker_rlimit_nofile 8192;
  '';

  services.nginx.eventsConfig = ''
    worker_connections 2048;
  '';

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
    shell = pkgs.zsh;
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
     fzf
  ];

  programs.zsh = {
    enable = true;

    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
    enableCompletion = true;

    histSize = 10000;
    histFile = "$HOME/.zsh_history";

    setOptions = [
      "HIST_IGNORE_DUPS"
      "SHARE_HISTORY"
      "HIST_IGNORE_SPACE"
      "HIST_FCNTL_LOCK"
    ];

    interactiveShellInit = ''
      # no NixOS option for this plugin, so source it directly
      source ${pkgs.zsh-history-substring-search}/share/zsh-history-substring-search/zsh-history-substring-search.zsh

      bindkey '^[[1;5C' forward-word
      bindkey '^[[1;5D' backward-word
      bindkey '^H' backward-delete-word
      bindkey '^[[A' history-substring-search-up
      bindkey '^[[B' history-substring-search-down

      if command -v fzf >/dev/null; then
        fzf-history-widget() {
          local selected
          selected=$(fc -rl 1 | fzf --tac +s --tiebreak=index --ansi --no-sort | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//')
          if [[ -n $selected ]]; then
            LBUFFER=$selected
          fi
        }
        zle -N fzf-history-widget
        bindkey '^R' fzf-history-widget
      fi
    '';

    # Runs at the very END of /etc/zshrc, after interactiveShellInit. The prompt
    # has to live here: the module's default promptInit would otherwise re-run
    # `prompt suse` down here and clobber anything the block above set up.
    promptInit = ''
      autoload -Uz promptinit
      promptinit
      prompt suse
      setopt prompt_sp

      RPROMPT='%F{green}[%*]%f'
    '';
  };

  services.clamav.daemon.enable = true;
  services.clamav.updater.enable = true;

  services.journald = {
    storage = "persistent";
  };

  system.stateVersion = "26.05";

}
