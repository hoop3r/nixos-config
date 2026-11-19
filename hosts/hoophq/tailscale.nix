{ config, pkgs, lib, ... }:

let
  extIface = "wlp0s20f3";

  # Read out of the HA module rather than repeating 8123 here -- that port is
  # declared once, in homeassistant.nix, and this way the funnel follows it.
  haPort = config.services.home-assistant.config.http.server_port;
in
{
  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "server";
    disableUpstreamLogging = true;

    extraSetFlags = [
      "--advertise-routes=192.168.1.0/24"
      "--advertise-exit-node"
      # Intentional, and NOT an oversight now that the tailnet resolves through
      # Pi-hole: the admin-console override points every *other* tailnet device
      # at 100.124.247.94, but this host must stay on Cloudflare because it
      # hosts that resolver. See "This host itself" in pihole.nix.
      "--accept-dns=false"
      "--stateful-filtering"
      "--ssh=false"
      "--shields-up=false"
      "--auto-update=false"
    ];
  };

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
    22
  ];

  systemd.services.tailscale-udp-gro = {
    description = "UDP GRO forwarding on ${extIface} for Tailscale route forwarding";
    bindsTo   = [ "sys-subsystem-net-devices-${extIface}.device" ];
    after     = [ "sys-subsystem-net-devices-${extIface}.device" ];
    wantedBy  = [
      "multi-user.target"
      "sys-subsystem-net-devices-${extIface}.device"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.ethtool}/bin/ethtool -K ${extIface} rx-udp-gro-forwarding on rx-gro-list off";
    };
  };


  # Home Assistant (8123) published to the public internet over Funnel.
  #
  # Why a unit and not an option: services.tailscale.serve in this nixpkgs
  # configures Tailscale SERVICES -- the `svc:`-prefixed VIP feature from
  # KB 1589, whose submodule is {advertised, endpoints}. That is a different
  # mechanism from node-level Funnel, which lives in tailscaled's ipn
  # ServeConfig and has no declarative option at all. So this is the CLI,
  # wrapped so a rebuild or a reboot reasserts it instead of leaving it as
  # undocumented console state -- the trap pihole.nix records for the tailnet
  # DNS override.
  #
  # What this does and does not expose:
  #   * Opens NO firewall port. tailscaled already holds the tunnel; Funnel
  #     connections arrive over it (direct or via DERP) and are proxied to
  #     127.0.0.1:8123. Nothing in networking.firewall needs to change, and
  #     homeassistant.nix keeps its tailnet-only bind.
  #   * Makes https://hoophq.tail072ce1.ts.net/ reachable by ANYONE on the
  #     internet. tailscaled terminates TLS with a real Let's Encrypt cert.
  #     HA's own auth is the only gate -- there is no Authentik forward-auth
  #     here, for the reason homeassistant.nix's bottom note gives (the
  #     companion app and webhooks cannot complete an interactive login).
  #   * Funnel supports only 443, 8443 and 10000 as public ports. 443 is the
  #     default and is what `--bg 8123` picks; it does NOT collide with
  #     nginx's 443, because tailscaled is listening on the tailnet address
  #     rather than on 0.0.0.0.
  #
  # ADMIN-CONSOLE PREREQUISITE, which Nix cannot set. Funnel is a tailnet-level
  # feature flag, so until it is turned on this unit runs, prints the notice
  # below and changes nothing:
  #
  #     Funnel is not enabled on your tailnet.
  #     To enable, visit:
  #     https://login.tailscale.com/f/funnel?node=nXr3ivRGHv11CNTRL
  #
  # That one URL is the whole job -- it grants the `funnel` node attribute AND
  # enables HTTPS certificates for the tailnet, so there is no separate ACL
  # edit and no separate DNS -> HTTPS Certificates step. The `?node=` value is
  # THIS node's stable ID; if it is ever rejected, re-run
  # `tailscale funnel --bg --yes 8123` by hand and use the URL it prints.
  #
  # The tell that certs are still off, checkable without touching the console:
  #     tailscale status --json | jq .CertDomains     # null => not enabled
  #
  # Note Tailscale's CLI exits 0 on that notice, so a green unit does NOT mean
  # the funnel is live. Verify with `tailscale funnel status`, which prints
  # "No serve config" until it actually is.
  #
  # The unit is deliberately NOT allowed to fail the boot over this -- see
  # the exit 0 at the end.
  systemd.services.tailscale-funnel-hass = {
    description = "Publish Home Assistant (8123) over Tailscale Funnel";
    after    = [ "tailscaled.service" "home-assistant.service" ];
    wants    = [ "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];
    path     = [
      config.services.tailscale.package
      pkgs.coreutils  # tr, seq, sleep
      pkgs.gnused     # BackendState parse
      pkgs.gnugrep    # funnel status check
    ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "180";
    };
    script = ''
      # tailscaled is up as soon as the unit starts, but it is not yet LOGGED
      # IN -- and `tailscale funnel` against a NeedsLogin backend fails rather
      # than waiting. Poll for Running the same way tailscale-addr-online
      # polls for the address.
      for _ in $(seq 1 120); do
        [ "$(tailscale status --json | tr -d ' "' | sed -n 's/^BackendState:\(.*\),$/\1/p')" = "Running" ] && break
        sleep 1
      done

      # --yes is required: without a tty the confirmation prompt Funnel shows
      # on first use is an error, not a default-yes.
      #
      # Do NOT branch on the exit status. When Funnel is not enabled on the
      # tailnet the CLI prints the "To enable, visit:" notice and still exits
      # 0, so trusting $? would log success while nothing was configured.
      # `funnel status` is the only honest check -- it prints "No serve
      # config" until a funnel actually exists.
      tailscale funnel --bg --yes ${toString haPort} || true

      if tailscale funnel status 2>&1 | grep -q "No serve config"; then
        echo "funnel NOT live -- Funnel is probably not enabled on the tailnet;" \
             "see the enablement URL in the comment above this unit" >&2
      else
        echo "funnel live: https://hoophq.tail072ce1.ts.net/ -> 127.0.0.1:${toString haPort}"
        tailscale funnel status
      fi

      # Never fail the boot over this. Funnel is remote convenience; the
      # tailnet path to HA works regardless, and a hard failure here would
      # also drag down anything ordered after multi-user.target.
      exit 0
    '';
  };
  services.nginx.virtualHosts."hoop3r.com".locations."= /.well-known/webfinger" = {
    extraConfig = ''
      default_type application/jrd+json;
      return 200 '{"subject":"acct:nicholas@hoop3r.com","links":[{"rel":"http://openid.net/specs/connect/1.0/issuer","href":"https://auth.hoop3r.com/application/o/tailscale/"}]}';
    '';
  };
}
