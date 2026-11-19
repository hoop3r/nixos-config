{ config, pkgs, lib, ... }:

# Network-wide DNS filtering, served from this host.
#
# Design notes / why it looks like this:
#
#   * The listen config is NONE + an explicit bind-dynamic, never ALL.
#     podman's aardvark-dns already owns 10.89.0.1:53 and 10.89.1.1:53 -- it is
#     what resolves container names inside the authentik_default and
#     mediastack_default networks. A bind on 0.0.0.0:53 takes those over and
#     silently breaks inter-container DNS. So the requirement is: bind named
#     interfaces only, never the wildcard.
#
#     Three of Pi-hole's five listeningModes are wrong here, for two different
#     reasons:
#       - ALL and SINGLE both bind the wildcard address (SINGLE merely filters
#         by arrival interface afterwards). Either one steals the podman ports.
#       - BIND emits dnsmasq's bind-interfaces, which binds named interfaces
#         only -- correct for aardvark, but it resolves the interface list once
#         at startup and *aborts* if a name is not present yet. FTL's own help
#         for this mode warns it "may result in issues when the interface may
#         go down (cable unplugged, etc.)".
#
#     That abort is not hypothetical; it caused a 2-day DNS outage starting
#     2026-11-05. lanIface is wifi, and a nixos-rebuild restarts wpa_supplicant
#     and pihole-ftl together. FTL won the race by two seconds, found
#     wlp0s20f3 mid-reassociation with no address, and logged:
#         dnsmasq: unknown interface wlp0s20f3
#         dnsmasq: FAILED to start up
#     The DNS engine died while FTL's main process stayed alive, so the unit
#     sat at "active (running)" with Restart=on-failure never firing, the
#     dashboard still serving, and every :53 socket accumulating queries that
#     nothing would ever answer. After=network.target does not help -- that
#     target says nothing about an address being assigned.
#
#     bind-dynamic is the fix, and is what dnsmasq recommends over
#     bind-interfaces anyway (FTL ships a "LOUD WARNING" to that effect). It
#     binds per-address rather than the wildcard, so aardvark stays intact,
#     but it tracks interfaces via netlink instead of resolving them once: a
#     name that does not exist yet is a warning, and the bind happens when the
#     interface appears. Verified against dnsmasq 2.93, the version FTL embeds:
#       bind-interfaces + interface=ghost0 -> "unknown interface ghost0", dies
#       bind-dynamic    + interface=ghost0 -> "warning: interface ghost0 does
#                                             not currently exist", stays up
#       bind-dynamic    + interface=lo     -> binds 127.0.0.1:53 and [::1]:53,
#                                             never 0.0.0.0:53
#
#     Because bind-dynamic and bind-interfaces are mutually exclusive ("cannot
#     set --bind-interfaces and --bind-dynamic"), listeningMode must be NONE --
#     the mode documented as "do not add any configuration concerning the
#     listening mode" -- and the whole listen config moves to dnsmasq_lines
#     below. Do not set listeningMode back to BIND and leave bind-dynamic in
#     place; FTL will refuse to start.
#
#   * upstreams are Cloudflare, NOT 192.168.1.1. The BGW320-500's resolver
#     strips RFC1918 answers from upstream responses, which is the whole
#     reason configuration.nix sets networking.nameservers by hand. Pointing
#     Pi-hole at the BGW would re-apply that filter to every query on the LAN
#     and break *.plex.direct for every client instead of just this host.
#     Re-measured 2026-10-26:
#       dig @192.168.1.1 10-89-0-1.sslip.io -> (empty)
#       dig @1.1.1.1     10-89-0-1.sslip.io -> 10.89.0.1
#     For the same reason, do not make the BGW a catch-all forwarder. The
#     domain-scoped dns.revServers entry below is a deliberate exception and
#     carries its own justification -- read it before touching it.
#
#   * openFirewall* are all false. Those options write
#     networking.firewall.allowedTCPPorts/allowedUDPPorts, which open the port
#     on EVERY interface. forensics.nix documents what that costs: a global
#     accept appears earlier in the chain than any interface-scoped rule, so
#     the scoped rule never matches a packet. Ports are opened per-interface
#     at the bottom of this file instead.
#
#   * This host does not use Pi-hole as its own resolver. networking.nameservers
#     stays on Cloudflare. See the note at the bottom.

let
  lanIface = "wlp0s20f3";

  # Same hardcoded tailnet v4 as containers.nix. tailscale0 gets this address
  # asynchronously after the interface appears, which is why the unit below
  # orders after tailscale-addr-online.service.
  tsAddr = "100.124.247.94";

  # 8089 is clear. Taken on this box: 22, 80, 443 (nginx), 6881 (gluetun),
  # 7878 (radarr), 8080 (qbittorrent), 8191 (byparr), 8989 (sonarr),
  # 9000 (authentik), 9696 (prowlarr), 25565, 32400/32401/32600 (plex).
  webPort = 8089;
in
{
  services.pihole-ftl = {
    enable = true;

    openFirewallDNS = false;
    openFirewallDHCP = false;
    # Also cannot be true once a port carries an address: the module derives
    # the firewall port by running toInt over the leading token of
    # settings.webserver.port, which throws on "127.0.0.1:8089".
    openFirewallWebserver = false;

    # Trim the query log on a timer rather than letting the FTL database grow
    # without bound. Defaults to 91 days.
    queryLogDeleter.enable = true;

    lists = [
      {
        url = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts";
        description = "Steven Black's unified adlist";
      }
    ];

    settings = {
      dns = {
        # See the header note: NONE means "emit no listening-mode config", and
        # the real listen config is the bind-dynamic block in dnsmasq_lines.
        # interface is still set because Pi-hole uses it for DHCP and for its
        # own auto-detection, but under NONE it is not what makes FTL listen.
        listeningMode = "NONE";
        interface = lanIface;

        upstreams = [
          "1.1.1.1"
          "1.0.0.1"
          "2606:4700:4700::1111"
          "2606:4700:4700::1001"
        ];

        # Forward ONLY attlocal.net and 1.168.192.in-addr.arpa to the BGW.
        # Format is "<enabled>,<cidr>,<server>,<domain>".
        #
        # This is the one place the BGW is used as a resolver, and it is safe
        # precisely because it is domain-scoped rather than a catch-all. The
        # BGW answers both of these zones out of its own DHCP lease table and
        # never forwards them upstream, so its RFC1918 answer-stripping -- the
        # thing that breaks *.plex.direct -- never engages. Measured
        # 2026-10-27:
        #   dig +short @192.168.1.1 -x 192.168.1.1   -> dsldevice.attlocal.net.
        #   dig +short @192.168.1.1 -x 192.168.1.209 -> hoophq.attlocal.net.
        #
        # It exists because of the tailnet override described at the bottom of
        # this file: a tailnet client sends *every* query here, including ones
        # for LAN names, even while it is sitting on the home wifi. Widening
        # the domain list, or dropping the domain entirely to make it a
        # catch-all, reintroduces the plex.direct bug for every tailnet device.
        #
        # What this does and does not buy, measured after activation on
        # 2026-10-27 -- the two directions are NOT equally useful:
        #
        #   * Reverse (PTR) is the real value. `dig -x 192.168.1.x` now returns
        #     the same names the BGW does (ArcherAX1800, HOOPBOX, ...) instead
        #     of NXDOMAIN. This is also what gives the Pi-hole dashboard
        #     readable client names instead of bare addresses.
        #   * Forward (A) is nearly inert, because the BGW publishes an A
        #     record only for ITSELF. dsldevice.attlocal.net -> 192.168.1.1
        #     resolves; HOOPBOX.attlocal.net does not, and never did -- it is
        #     empty straight from 192.168.1.1 too. Do not spend time debugging
        #     that as a Pi-hole problem; the BGW is PTR-only for clients.
        #
        # Proof the queries reach the BGW rather than leaking upstream:
        #   dig +short @1.1.1.1  dsldevice.attlocal.net -> (empty)
        #   dig +short @192.168.1.1 dsldevice.attlocal.net -> 192.168.1.1
        #   dig +short @100.124.247.94 dsldevice.attlocal.net -> 192.168.1.1
        revServers = [
          "true,192.168.1.0/24,192.168.1.1,attlocal.net"
        ];

        domainNeeded = true;
        expandHosts = true;
      };

      misc = {
        # The dashboard is allowed to change settings at runtime. Note this
        # does NOT make them persistent: /etc/pihole/pihole.toml is installed
        # by environment.etc with a mode set, so activation copies it out of
        # the nix store and every nixos-rebuild discards whatever the UI
        # wrote. Treat the UI as a scratchpad and copy anything worth keeping
        # back into this file.
        readOnly = false;

        # The entire listen config, because listeningMode is NONE. Pi-hole's
        # own config models exactly one interface anyway, so a second one
        # always had to come in as a raw dnsmasq line.
        #
        # bind-dynamic must come with the interface= lines it governs. Unlike
        # the old BIND/bind-interfaces setup, naming an interface that is
        # absent at startup is now safe: it warns and binds later, which is
        # the whole point -- lanIface is wifi and is briefly gone mid-rebuild.
        #
        # lo is listed explicitly. bind-dynamic binds only what is named here
        # and does not add loopback for you, and dropping it would take away
        # 127.0.0.1:53 -- which is what `dig @127.0.0.1` uses to verify this
        # host after a rebuild. It does not make the box resolve through
        # Pi-hole; networking.nameservers is unchanged (see the note at the
        # bottom).
        #
        # Still do NOT add the podman bridges (podman1/podman2, 10.89.x.1) to
        # this list. aardvark-dns owns those, and the header note says why.
        dnsmasq_lines = [
          "bind-dynamic"
          "interface=lo"
          "interface=${lanIface}"
          "interface=tailscale0"
        ];
      };

      # Required for services.pihole-ftl.lists to be loaded via the API on
      # startup; enables an ephemeral password for the `pihole` command.
      webserver.api.cli_pw = true;
    };
  };

  services.pihole-web = {
    enable = true;
    hostName = "pi.hole";

    # Address-scoped, mirroring how the *arr admin UIs are published in
    # containers.nix: loopback plus the tailnet address, never 0.0.0.0. The
    # trailing "o" marks the tailnet bind optional so a missing address at
    # startup is not fatal.
    ports = [
      "127.0.0.1:${toString webPort}"
      "${tsAddr}:${toString webPort}o"
    ];
  };

  # Reuse the existing readiness oneshot from containers.nix rather than
  # adding a second poller for the same address.
  systemd.services.pihole-ftl.after = [ "tailscale-addr-online.service" ];

  # An API password, which this host deliberately did without until
  # 2026-11-08. It exists now for exactly one reason: Home Assistant's pi_hole
  # integration cannot talk to a passwordless Pi-hole v6.
  #
  # Why a dummy value does not work, since that is the obvious first thing to
  # try. FTL answers POST /api/auth with HTTP 200 and session.valid = true even
  # when the password is wrong, but sets session.sid to null:
  #     {"session":{"valid":true,"sid":null,"message":"password incorrect"}}
  # and the `hole` client HA uses raises on exactly that --
  # `if not self._session_id: raise HoleError("Authentication failed: No
  # session ID received")`. An empty password would be fine (hole's v6
  # authenticate() short-circuits with `if not self.password: return`) but
  # HA's config flow declares the field vol.Required, so the UI will not
  # accept one. A real password is the only way through.
  #
  # Why this is NOT the thing the note at the bottom of this file warns
  # against: that warning is about `settings`, which renders into a
  # world-readable /nix/store path. This password never goes near the store.
  # It is generated once into a 0400 root-only file and handed to FTL through
  # its FTLCONF_ environment override, which takes precedence over
  # pihole.toml -- and that matters here because activation rewrites
  # pihole.toml from the store on every rebuild, so anything written into the
  # toml (by the UI or otherwise) would not survive. The env override is
  # reapplied on every start instead, making it self-healing.
  #
  # How to confirm FTL actually took the override: its startup banner counts
  # them, and before this change it read "0 entries are forced through
  # environment". It should now be 1:
  #     journalctl -u pihole-ftl | grep 'forced through environment'
  # FTL also logs "Config option <x> is read-only (set via environmental
  # variable)" for anything it picked up this way.
  #
  # Fallback if the plaintext key is ever rejected: webserver.api.password is a
  # write-only setter (FTL hashes it and writes only a placeholder back into
  # the toml), and the hashed sibling can be set instead --
  # `pihole-FTL --hash` produces the value for
  # FTLCONF_webserver_api_pwhash. Only reach for that if the banner stays at 0.
  #
  # To read it (to paste into Home Assistant's "API key" field):
  #     sudo cat /var/lib/pihole-api/password
  # To rotate: delete that file and `systemctl restart pihole-api-password
  # pihole-ftl`, then update the HA config entry.
  systemd.services.pihole-api-password = {
    description = "Generate Pi-hole API password outside the nix store";
    wantedBy = [ "pihole-ftl.service" ];
    before = [ "pihole-ftl.service" ];
    path = [ pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -u
      d=/var/lib/pihole-api
      install -d -m 0700 -o root -g root "$d"

      # Generated once and then left alone, so the password is stable across
      # reboots and rebuilds and the HA config entry keeps working.
      #
      # head -c on /dev/urandom rather than `tr -dc < /dev/urandom | head`:
      # the latter leaves tr reading an infinite stream and relying on SIGPIPE
      # to stop, which under systemd's `set -e` can fail the unit. Bounding
      # the read first makes every stage in the pipe terminate on its own.
      # Alphanumeric only, so the value needs no quoting in the env file.
      if [ ! -s "$d/password" ]; then
        umask 077
        head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | cut -c1-32 \
          > "$d/password"
        chmod 0400 "$d/password"
      fi

      umask 077
      printf 'FTLCONF_webserver_api_password=%s\n' "$(cat "$d/password")" \
        > "$d/env"
      chmod 0400 "$d/env"
    '';
  };

  # The leading "-" makes this optional, and that is load-bearing rather than
  # defensive: without it a missing or unreadable env file makes systemd refuse
  # to start pihole-ftl at all, which would take DNS down for the whole tailnet
  # to protect a dashboard login. Given this host has already lost DNS for two
  # days once (see the header note), nothing about the password is allowed to
  # become a hard dependency of the resolver starting.
  systemd.services.pihole-ftl.serviceConfig.EnvironmentFile =
    "-/var/lib/pihole-api/env";

  # Unlike a podman-published port, a native service's traffic traverses the
  # INPUT chain, so these rules are load-bearing rather than decorative.
  # Deliberately scoped: 53 is reachable from the LAN and the tailnet and
  # nowhere else. The BGW forwards nothing to this host, so there is no path
  # from the WAN, and an open resolver on the internet is a reflector.
  networking.firewall.interfaces = {
    ${lanIface} = {
      allowedUDPPorts = [ 53 ];
      allowedTCPPorts = [ 53 ];
    };
    "tailscale0" = {
      allowedUDPPorts = [ 53 ];
      allowedTCPPorts = [ 53 webPort ];
    };
  };
}

# =============================================================================
# WHO ACTUALLY RESOLVES THROUGH THIS -- AND WHO DOES NOT
# =============================================================================
#
# Short version, as of 2026-10-27: the tailnet does, the LAN does not, and the
# LAN cannot be made to without this host taking over DHCP.
#
# -- The tailnet (covered) ----------------------------------------------------
#   Configured in the Tailscale admin console, NOT here -- there is no API key
#   in hosts/hoophq/secrets, so this is console state with no declarative
#   counterpart. https://login.tailscale.com/admin/dns
#
#     Global nameservers:    100.124.247.94   (this host)
#                            1.1.1.1          (fallback)
#     Override DNS servers:  on
#     MagicDNS:              on
#
#   Order is deliberate. Tailscale hands both to the client in preference
#   order and advances to 1.1.1.1 only on failure, never on NXDOMAIN -- so a
#   blocked domain stays blocked, while this host being offline or mid-rebuild
#   degrades to one slow-then-unfiltered query instead of to no DNS at all.
#   That tradeoff was chosen knowingly: the alternative (Pi-hole as the sole
#   nameserver) means closing this laptop's lid takes DNS down for every
#   tailnet device, everywhere.
#
#   MagicDNS is unaffected by the override. `tailscale dns status` shows a
#   split route for ts.net. -> 199.247.155.53, which is consulted before a
#   query can reach a global nameserver, so *.tail072ce1.ts.net keeps
#   resolving and Pi-hole never sees those queries.
#
#   Prerequisite before flipping the override: the tailnet policy must permit
#   *:53 to this host. The default allow-all ACL does. If a custom policy ever
#   blocks 53, every tailnet device loses DNS the moment the toggle is on --
#   this is the single failure mode the Tailscale docs call out by name.
#
#   Rollback is one toggle in the console, effective in seconds, no rebuild.
#
# -- The LAN (not covered) ----------------------------------------------------
#   An earlier version of this comment claimed the DHCP-advertised DNS server
#   could be changed in the BGW UI under Home Network -> Subnets & DHCP. That
#   is true of the BGW210 and 5268AC but NOT of the BGW320-500: AT&T removed
#   DNS-server editing on this model, and that page offers only
#   "DHCP Server Enable = Off". Do not go looking for the field.
#
#   There is no other injection point. The TP-Link (BUGBYTE01) runs in
#   AP/bridge mode, so the entire house is one 192.168.1.0/24 with the BGW
#   (90:d0:92:ed:4a:41) as the only router and the only DHCP server. DHCP
#   option 6 is the only automatic way to tell a LAN client which resolver to
#   use, so the only automatic option left is for pihole-FTL to own DHCP
#   itself. That was considered and declined.
#
#   What that leaves unfiltered:
#     * every LAN-only device -- TVs, consoles, IoT. Anything personally owned
#       is on the tailnet instead and is covered by the override above, on the
#       home wifi as well as off it.
#     * IPv6, for everything. The BGW advertises itself
#       (2600:1700:8870:e4c0::1) as a resolver over both DHCPv6 and RA, and
#       this host cannot override an RA it does not originate. pihole-FTL does
#       already listen on v6 on lanIface -- dnsmasq's interface= covers both
#       families -- so the gap is purely what the BGW advertises. The only fix
#       is disabling LAN IPv6 on the BGW.
#
#   If this is ever revisited, the shape of the DHCP handover is: set
#   "DHCP Server Enable = Off" on the BGW, enable settings.dhcp.* here, give
#   this host a static 192.168.1.209 (NetworkManager currently leases it --
#   connection "BUGBYTE01"), migrate the BGW's reservations into dhcp.hosts,
#   and add no-dhcp-interface=tailscale0 to dnsmasq_lines so dnsmasq does not
#   try to serve DHCP over the tunnel. Note the lease file path is hardcoded
#   by Pi-hole and the nixos module cannot override it (see the TODO in
#   nixos/modules/services/networking/pihole-ftl.nix).
#
#   Independent of all that, keep the BGW's DHCP reservation pinning this host
#   to 192.168.1.209 (wifi MAC bc:6e:e2:b2:9d:91). The revServers entry above
#   and the lanIface bind both assume that address.
#
# -- This host itself (deliberately not covered) ------------------------------
#   networking.nameservers in configuration.nix stays pointed at Cloudflare.
#   Pointing it at 127.0.0.1 would make this box depend on a resolver it
#   hosts, and several things on it need DNS before or independently of
#   pihole-FTL:
#
#     * services.pihole-ftl.lists is fetched over HTTPS by pihole-ftl-setup
#     * ACME renewal for the nginx vhosts
#     * cloudflare-ips.service, which refreshes the cf4/cf6 ipsets that gate
#       80/443 -- if it fails, the ipsets go stale
#     * podman image pulls for the auto-update timer
#
#   Any of those running while FTL is down or mid-activation would fail, and
#   the failure mode is confusing. The cost is that this host's own queries
#   are unfiltered.
#
#   The console change above does not touch this host: tailscale.nix runs
#   --accept-dns=false, so tailscaled never writes resolv.conf here. That flag
#   looks like an oversight once you know the tailnet resolves through
#   Pi-hole; it is not. Leave it alone.
#
# -- Reaching the dashboard ---------------------------------------------------
#   Over the tailnet:   http://100.124.247.94:8089/
#   Or an ssh tunnel:   ssh -L 8089:127.0.0.1:8089 bugbyte@hoophq
#
#   Note the path is "/", not "/admin/". services.pihole-web sets
#   webserver.paths.webhome = "/", so /admin/ 404s.
#
#   As of 2026-11-08 there IS a password, but it is deliberately not set
#   through `settings`. Do not move it there: settings render into a
#   world-readable nix store path, so a password written there would be
#   published to every user on the box. It is generated into
#   /var/lib/pihole-api/password (0400 root) and injected via the
#   FTLCONF_webserver_api_password environment override -- see
#   pihole-api-password.service above for why, and for how to read or rotate
#   it. Tailnet-only binding is still the primary access control; the password
#   exists because Home Assistant requires one, not because the binding was
#   considered insufficient. Do not add an nginx vhost for this without
#   putting Authentik in front of it.
#
#   Consequence to know about: the API is no longer anonymous, so a bare
#   `curl http://127.0.0.1:8089/api/...` now returns 401. Authenticated calls
#   are two steps -- POST the password to /api/auth for a session id, then send
#   it as the X-FTL-SID header:
#     pw=$(sudo cat /var/lib/pihole-api/password)
#     sid=$(curl -s -X POST http://127.0.0.1:8089/api/auth \
#             -H 'Content-Type: application/json' \
#             -d "{\"password\":\"$pw\"}" \
#           | sed -n 's/.*"sid":"\([^"]*\)".*/\1/p')
#     curl -s -H "X-FTL-SID: $sid" \
#       'http://127.0.0.1:8089/api/stats/top_clients?blocked=true&count=5'
#   That top_clients call is the check that proves the tailnet DNS override is
#   live (a tailnet client appearing there with a nonzero blocked count), so it
#   is worth keeping working rather than rediscovering the 401 later.
# =============================================================================
