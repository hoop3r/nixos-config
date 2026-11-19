# Wazuh 4.14.10 -- the whole SIEM server stack on this one box.
#
# Three services from the github:nealfennimore/wazuh-nixos flake input:
#
#   wazuh-indexer    OpenSearch. Stores alerts. 127.0.0.1+127.0.0.2:9200.
#   wazuh-server     The manager: remoted, analysisd, authd, the API, filebeat.
#   wazuh-dashboard  OpenSearch Dashboards. The browser UI, on the tailnet.
#
# Data flow: an agent enrolls against authd on 1515 and then ships events to
# remoted on 1514. analysisd turns them into alerts in
# /var/ossec/logs/alerts/alerts.json, wazuh-filebeat ships those to the indexer
# as wazuh-alerts-4.x-*, and the dashboard reads the indexer plus the manager
# API on 55000.
#
# EVERYTHING IS TAILNET-ONLY. Nothing here is behind nginx, has an ACME
# certificate, or is reachable from Cloudflare. The dashboard binds tsAddr
# directly; the agent ports are opened on tailscale0 and nowhere else. That is
# a deliberate choice, not an oversight: see the warning in pihole.nix about
# never exposing an admin UI here without Authentik in front of it. If this
# ever does need a public vhost, the forward-auth helpers are already sitting
# unused in services/webserver.nix (authentikForwardAuth / authentikLocations),
# and services/webserver.nix.bak-1790970501 has the working usage pattern.
#
# WHY THERE IS NO AGENT ON THIS HOST
# services.wazuh-agent and services.wazuh-server cannot coexist -- both own
# /var/ossec and the `wazuh` user, and the modules assert against it. hoophq is
# still monitored: the manager runs its own wazuh-syscheckd, wazuh-logcollector
# and rootcheck against this filesystem and this journal. The only thing lost
# versus a real agent is the NixOS package-inventory collector.
#
# The macOS side lives in ../mcpro/wazuh-agent.nix. That flake has no darwin
# outputs, so mcpro installs the official upstream .pkg instead -- read that
# file before touching enrollment here, the two share AUTHD_PASS and the CA.
#
# FOOTPRINT. Measured on this host 2026-11-19, ~1h after the first switch,
# MemoryCurrent per unit, no agents enrolled yet:
#
#   wazuh-indexer     2607 MiB   the JVM, capped at 2g heap (heapSize below)
#   wazuh-modulesd    1997 MiB   <- the surprise; see below
#   wazuh-dashboard    264 MiB
#   wazuh-apid         245 MiB
#   everything else    ~110 MiB  analysisd, filebeat, db, remoted, syscheckd...
#   ----------------------------
#   total             5116 MiB
#
# That is well above the 3.5-4 GB this file originally estimated, and the whole
# difference is wazuh-modulesd. It is not a leak: modulesd runs the 4.x
# vulnerability detector, which holds the CVE content database in memory, and
# it stands up a dozen indexer connectors on startup
# (wazuh-states-vulnerabilities-hoophq, wazuh-states-inventory-*-hoophq).
# Budget ~2 GB for it and do not be alarmed by the number.
#
# Headroom after this: 7.6 GiB available of 15 GiB, alongside Home Assistant,
# Plex, the 12 mediastack containers and nginx. Comfortable but not generous --
# `free -h` before adding anything large, and if the box starts swapping, drop
# heapSize to 1g before touching anything else.
#
# Disk: / went from 87% to 65% used (157 GB free) when space was cleared for
# this. Index data at 30 day retention for two endpoints is low single-digit
# GB. Check `df -h /` before adding agents and before flipping logAll on.
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  # The tailnet identity of this host. tsAddr is the same literal the mediastack
  # containers, pihole-web and Home Assistant bind; tsName is what MagicDNS
  # hands out and therefore what mcpro connects to.
  tsAddr = "100.124.247.94";
  tsName = "hoophq.tail072ce1.ts.net";

  # Runtime PKI, generated on this host by wazuh-pki.service below and
  # deliberately NOT in the nix store. These are plain strings, not Nix paths:
  # a path literal would be copied into the store, which is world-readable, and
  # the modules' fileOption type wants a runtime path anyway.
  pki = "/var/lib/secrets/wazuh";
  caFile = "${pki}/ca.pem";

  # The flake's OWN package outputs -- NOT the modules' package defaults.
  #
  # This line is the difference between a 1.2 GB download and a multi-hour
  # compile, and it is not obvious. Each module defaults its package to
  # `pkgs.callPackage ../../pkgs/wazuh-<component> { }`, and inside a NixOS
  # module `pkgs` is OUR pkgs -- nixos-26.05. The wazuh flake's CI populates
  # wazuh.cachix.org by building `.#packages.x86_64-linux.*` against the
  # flake's own locked nixpkgs (nixos-unstable, 0ae2bc14). Different nixpkgs,
  # different derivation hash, so the module defaults are a guaranteed cache
  # miss. Verified 2026-11-19: the default out-paths return 404 from both
  # cache.nixos.org and wazuh.cachix.org, while these return 200.
  #
  # pkgs.wazuh-server is the one that really hurts to miss -- it compiles the
  # manager daemons, the Python API framework and a bundled CPython from
  # upstream source.
  #
  # Cost of pinning these: a second closure (its own glibc, openjdk, node)
  # alongside the system's. Worth it, but it is why the disk note in the header
  # says 2-3 GB rather than a few hundred MB.
  wazuhPkgs = inputs.wazuh.packages.${pkgs.stdenv.hostPlatform.system};

  # Delete time-series indices 30 days after creation.
  #
  # The indexer module has no ISM option, so this goes in through the API via
  # wazuh-indexer-retention.service. Written as Nix rather than a heredoc so
  # the JSON cannot drift out of shape and so there is no shell quoting to get
  # wrong. ism_template binds the policy to indices created AFTER the policy
  # exists, which is why the unit also runs an explicit _ism/add over any
  # indices that already exist.
  #
  # DELIBERATELY EXCLUDED: wazuh-states-inventory and
  # wazuh-states-vulnerabilities. Those hold CURRENT state, not a time series,
  # so there is no old data in them to expire -- an age-based delete there
  # would throw away the live package inventory and the current vulnerability
  # findings and call it housekeeping. Only ever add dated/rolling patterns to
  # the list below.
  retentionId = "wazuh-retention-30d";
  retentionPolicy = pkgs.writeText "${retentionId}.json" (builtins.toJSON {
    policy = {
      description = "Delete Wazuh alert and archive indices 30 days after creation.";
      default_state = "hot";
      states = [
        {
          name = "hot";
          actions = [ ];
          transitions = [
            {
              state_name = "delete";
              conditions.min_index_age = "30d";
            }
          ];
        }
        {
          name = "delete";
          actions = [ { delete = { }; } ];
          transitions = [ ];
        }
      ];
      ism_template = [
        {
          index_patterns = [
            "wazuh-alerts-4.x-*"
            "wazuh-archives-4.x-*"
            # Weekly rolling indices the dashboard creates (observed
            # wazuh-monitoring-2026.47w and wazuh-statistics-2026.47w on the
            # first boot). Small per week, but nothing else prunes them, so
            # without these two patterns they grow for as long as the box runs.
            "wazuh-monitoring-*"
            "wazuh-statistics-*"
          ];
          priority = 100;
        }
      ];
    };
  });
in
{
  imports = [
    inputs.wazuh.nixosModules.wazuh-indexer
    inputs.wazuh.nixosModules.wazuh-server
    inputs.wazuh.nixosModules.wazuh-dashboard
  ];

  # `extra-` and NOT plain `substituters`/`trusted-public-keys`: those two
  # REPLACE their defaults rather than merging, so assigning them would drop
  # cache.nixos.org and send the whole system closure to a local build. Same
  # replace-not-merge trap as services.home-assistant.extraComponents.
  #
  # CHICKEN AND EGG, and it bites exactly once. This setting lands in
  # /etc/nix/nix.conf only AFTER the switch that builds it, and nixos-rebuild
  # uses the nix daemon of the CURRENTLY running generation. nix.settings.
  # trusted-users on this host is `root` alone, so an unprivileged
  # `--option extra-substituters` is ignored outright. For the FIRST build,
  # pass the cache to the privileged invocation:
  #
  #   sudo nixos-rebuild switch --flake .#hoophq \
  #     --option extra-substituters https://wazuh.cachix.org \
  #     --option extra-trusted-public-keys \
  #       'wazuh.cachix.org-1:NflEnqc62gXNPSzRtdOmuzDyfGK7yrTc6C2znraX3B8='
  #
  # `--accept-flake-config` works too -- the wazuh flake declares the same
  # cache in its nixConfig -- but it accepts whatever that flake asks for, now
  # and on every future update, so the explicit form is preferable. Every
  # rebuild after the first picks this up from the system config.
  nix.settings = {
    extra-substituters = [ "https://wazuh.cachix.org" ];
    extra-trusted-public-keys = [
      "wazuh.cachix.org-1:NflEnqc62gXNPSzRtdOmuzDyfGK7yrTc6C2znraX3B8="
    ];
  };

  # --------------------------------------------------------------------- PKI --
  #
  # An internal CA, because there is no alternative. The indexer's security
  # plugin authenticates its own node over mTLS against an exact certificate
  # subject DN (plugins.security.nodes_dn) and grants superuser to another exact
  # DN (plugins.security.authcz.admin_dn). An ACME certificate cannot carry
  # either, and nothing public should be able to issue a cert that the indexer
  # treats as its own node.
  #
  # Modelled on pihole-api-password in pihole.nix: generate once into
  # /var/lib/secrets, 0700 root, never into the nix store, and leave it alone
  # afterwards so the identities are stable across reboots and rebuilds.
  #
  # The CA is created once and then never touched -- rotating it would break
  # mcpro, which pins it as <server_ca_path>. Leaves ARE re-issued when their
  # spec changes: each one records "cn=... san=..." in a .spec file and is
  # regenerated when that string no longer matches. So adding a SAN here is a
  # rebuild, not a manual rm. It is NOT a restart, though -- the services read
  # their certs through LoadCredential at start, so after a re-issue run:
  #
  #   sudo systemctl restart wazuh-indexer wazuh-dashboard wazuh-server.target
  #
  # Four identities, and the CNs are deliberately all different:
  #
  #   indexer    CN=hoophq           the node certificate. CN tracks nodeName,
  #                                  which defaults to networking.hostName, and
  #                                  securityadmin verifies it as admin.host --
  #                                  also hostName by default, which /etc/hosts
  #                                  maps to 127.0.0.2. That is exactly why the
  #                                  module's default listenAddress includes
  #                                  127.0.0.2, so both are left at default.
  #   admin      CN=admin            securityadmin client cert; a superuser by
  #                                  DN, which is what the retention unit uses
  #                                  instead of a password.
  #   server     CN=wazuh-server     does triple duty: the API cert the
  #                                  dashboard verifies, the authd cert mcpro
  #                                  verifies at enrollment, and filebeat's
  #                                  client cert to the indexer. Hence the wide
  #                                  SAN list.
  #   dashboard  CN=wazuh-dashboard  browser-facing, so tsName and tsAddr.
  #
  # CN=wazuh-server must NOT equal the indexer's node CN. If filebeat presented
  # a certificate whose DN is in nodes_dn, the indexer would treat the manager
  # as a cluster node rather than as a client authenticating with a password.
  systemd.services.wazuh-pki = {
    description = "Generate the Wazuh internal CA and leaf certificates";
    wantedBy = [ "multi-user.target" ];
    # requiredBy, not just before: if certificate generation fails we want the
    # consumers to refuse to start and say so, rather than each failing later
    # and separately on a missing LoadCredential source.
    requiredBy = [
      "wazuh-indexer.service"
      "wazuh-dashboard.service"
      "wazuh-server-setup.service"
    ];
    before = [
      "wazuh-indexer.service"
      "wazuh-dashboard.service"
      "wazuh-server-setup.service"
      "wazuh-filebeat.service"
    ];
    path = [
      pkgs.openssl
      pkgs.coreutils
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail

      d=${pki}
      install -d -m 0700 -o root -g root "$d"

      # The CA certificate is public -- mcpro has to fetch it to verify authd --
      # so a readable copy lives outside the 0700 directory. The CA *key* never
      # leaves it.
      install -d -m 0755 -o root -g root /var/lib/wazuh-ca

      cd "$d"
      umask 077

      if [ ! -s ca.pem ]; then
        echo "creating the Wazuh CA"
        openssl req -x509 -newkey rsa:4096 -nodes -days 3650 -sha256 \
          -subj "/OU=Wazuh/O=Wazuh/CN=hoophq-wazuh-ca" \
          -keyout ca.key -out ca.pem
        chmod 0600 ca.key
        chmod 0644 ca.pem
      fi
      install -m 0644 ca.pem /var/lib/wazuh-ca/ca.pem

      issue() {
        name="$1"
        cn="$2"
        san="$3"
        spec="cn=$cn san=$san"

        if [ -s "$name.pem" ] && [ -s "$name-key.pem" ] \
           && [ "$(cat "$name.spec" 2>/dev/null || true)" = "$spec" ]; then
          return 0
        fi

        echo "issuing $name: $spec"
        openssl req -newkey rsa:2048 -nodes \
          -subj "/OU=Wazuh/O=Wazuh/CN=$cn" \
          -keyout "$name.rsa.key" -out "$name.csr"
        printf 'subjectAltName=%s\nextendedKeyUsage=serverAuth,clientAuth\n' \
          "$san" > "$name.ext"
        openssl x509 -req -in "$name.csr" -CA ca.pem -CAkey ca.key \
          -CAcreateserial -days 3650 -sha256 -extfile "$name.ext" \
          -out "$name.pem"
        # PKCS#8, not PKCS#1. The indexer rejects PKCS#1 outright.
        openssl pkcs8 -topk8 -nocrypt -in "$name.rsa.key" -out "$name-key.pem"
        openssl verify -CAfile ca.pem "$name.pem" >/dev/null
        rm -f "$name.rsa.key" "$name.csr" "$name.ext"
        chmod 0600 "$name-key.pem"
        chmod 0644 "$name.pem"
        printf '%s' "$spec" > "$name.spec"
      }

      issue indexer hoophq \
        "DNS:hoophq,DNS:localhost,IP:127.0.0.1,IP:127.0.0.2"
      issue admin admin \
        "DNS:admin"
      issue server wazuh-server \
        "DNS:hoophq,DNS:${tsName},DNS:localhost,IP:127.0.0.1,IP:127.0.0.2,IP:${tsAddr}"
      issue dashboard wazuh-dashboard \
        "DNS:hoophq,DNS:${tsName},IP:${tsAddr}"

      # Usernames. Not secret, but the modules take them as file paths, and
      # keeping them next to the certificates means one directory holds
      # everything the units load as credentials.
      printf 'admin'        > indexer-username
      printf 'kibanaserver' > dashboard-indexer-username
      printf 'wazuh-wui'    > api-wui-username
      chmod 0644 indexer-username dashboard-indexer-username api-wui-username
    '';
  };

  # ----------------------------------------------------------------- indexer --
  services.wazuh-indexer = {
    enable = true;
    package = wazuhPkgs.wazuh-indexer;

    # NEVER use a module's openFirewall on this host. nixos-fw evaluates the
    # global accept before any interface-scoped rule, so a global open port
    # makes every `networking.firewall.interfaces` rule below dead code. The
    # same rule is written up in pihole.nix, homeassistant.nix and
    # services/webserver.nix. Here it is doubly moot -- the indexer is loopback
    # only and nothing off-box should ever reach 9200.
    openFirewall = false;

    # listenAddress, port, transportPort, nodeName, clusterName and singleNode
    # are all left at their defaults on purpose. The default listenAddress is
    # [ "127.0.0.1" "127.0.0.2" ] and nodeName/admin.host default to
    # networking.hostName -- which /etc/hosts resolves to 127.0.0.2 -- so
    # securityadmin can verify the node certificate's DNS:hoophq SAN over
    # loopback. Overriding any of them means re-deriving the other three.

    # 1g is the module default and OpenSearch will GC-thrash on it as soon as
    # there is more than a token amount of data. 2g leaves roughly 8 GB for
    # Home Assistant, Plex, the 12 mediastack containers and nginx. Revisit if
    # agents or retention grow -- the index data budget is in the header.
    heapSize = "2g";

    nodeDistinguishedNames = [ "CN=hoophq,O=Wazuh,OU=Wazuh" ];
    tls = {
      ca = caFile;
      certificate = "${pki}/indexer.pem";
      key = "${pki}/indexer-key.pem";
    };
    admin = {
      certificate = "${pki}/admin.pem";
      key = "${pki}/admin-key.pem";
      distinguishedNames = [ "CN=admin,O=Wazuh,OU=Wazuh" ];
    };

    # Hashes, because internal_users.yml stores bcrypt. The matching plaintext
    # is what the manager and the dashboard authenticate with below. Both forms
    # are in secrets/wazuh.yaml -- see the rotation note in secrets/sops.nix.
    users = {
      admin = {
        passwordHashFile = config.sops.secrets.wazuh_indexer_admin_hash.path;
        backendRoles = [ "admin" ];
      };
      kibanaserver.passwordHashFile =
        config.sops.secrets.wazuh_indexer_kibanaserver_hash.path;
    };
  };

  # ------------------------------------------------------------------ server --
  services.wazuh-server = {
    enable = true;
    package = wazuhPkgs.wazuh-server;

    # See the indexer note. 1514/1515/55000 are opened on tailscale0 at the
    # bottom of this file instead.
    openFirewall = false;

    auth = {
      enable = true;
      passwordFile = config.sops.secrets.wazuh_authd_pass.path;
      # The certificate mcpro verifies at enrollment, which is why its SAN
      # carries tsName.
      tls = {
        certificate = "${pki}/server.pem";
        key = "${pki}/server-key.pem";
      };
      # NOTE on re-enrollment, deliberately left at upstream defaults.
      #
      # The module emits no <force> block (generate-server-config.nix:142
      # builds <auth> from disabled/port/ipv6/use_source_ip/purge/use_password/
      # ciphers/ssl_* only), so authd uses its compiled-in defaults: force
      # enabled, key_mismatch yes, disconnected_time 1h. Practical effect --
      # reinstalling the agent on mcpro works if it has been offline for an
      # hour, and is refused as "name already taken" if it is still online.
      #
      # auth.settings IS available and recursiveUpdates over those defaults, so
      # a <force> block with disconnected_time 0 could make replacement
      # unconditional. It is not set here on purpose: that XML has not been
      # validated against a running manager, and a value authd rejects makes
      # authd refuse to start, which takes enrollment down completely. The
      # manual fix costs one command and is never a surprise:
      #
      #   sudo /var/ossec/bin/manage_agents -r <id>   # then re-enroll mcpro
      #
      # If this turns out to be a recurring annoyance, add it then and verify
      # with `grep -A8 '<force>' /var/ossec/etc/ossec.conf` plus
      # `systemctl status wazuh-authd` before trusting it.
    };

    api = {
      tls = {
        certificate = "${pki}/server.pem";
        key = "${pki}/server-key.pem";
      };
      # Default is [ "0.0.0.0" "::" ]. Narrowed to loopback plus the tailnet:
      # 127.0.0.2 is here because the dashboard reaches the API as
      # https://hoophq, which /etc/hosts resolves to 127.0.0.2.
      listenAddresses = [
        "127.0.0.1"
        "127.0.0.2"
        tsAddr
      ];
      users = {
        wazuh.passwordFile = config.sops.secrets.wazuh_api_wazuh_pass.path;
        wazuh-wui.passwordFile = config.sops.secrets.wazuh_api_wui_pass.path;
      };
    };

    indexer = {
      hosts = [ "https://hoophq:9200" ];
      tls = {
        ca = caFile;
        certificate = "${pki}/server.pem";
        key = "${pki}/server-key.pem";
      };
      usernameFile = "${pki}/indexer-username";
      passwordFile = config.sops.secrets.wazuh_indexer_admin_pass.path;
    };

    # Pinned for the same cache reason as the three packages above:
    # filebeat.package defaults to pkgs.callPackage ../../pkgs/filebeat-oss,
    # which extracts the upstream filebeat OSS 7.10.2 rpm and so drags in rpm,
    # rpm-sequoia and rpmextract as build-time deps against our nixpkgs. The
    # flake's output is prebuilt and cached.
    filebeat.package = wazuhPkgs.filebeat-oss;

    # logAll archives EVERY decoded event to logs/archives/archives.json,
    # alerts or not. It is the single fastest way to fill a disk that was
    # already at 87%, and the retention policy above does not cover a flat file
    # on /. Leave it off unless you are actively hunting something and are
    # watching `df`.
    logAll = false;
  };

  # --------------------------------------------------------------- dashboard --
  services.wazuh-dashboard = {
    enable = true;
    package = wazuhPkgs.wazuh-dashboard;
    openFirewall = false;

    # A single address, not a list -- the option is a string, because it becomes
    # OpenSearch Dashboards' server.host. So this is tsAddr and nothing else:
    # there is no loopback bind to fall back on, which is the whole point.
    listenAddress = tsAddr;

    tls = {
      certificate = "${pki}/dashboard.pem";
      key = "${pki}/dashboard-key.pem";
    };

    indexer = {
      hosts = [ "https://hoophq:9200" ];
      ca = caFile;
      usernameFile = "${pki}/dashboard-indexer-username";
      passwordFile = config.sops.secrets.wazuh_indexer_kibanaserver_pass.path;
    };

    managers = [
      {
        # An origin: no port, no path, no trailing slash. The module asserts on
        # all three. The port is a separate attribute below.
        url = "https://hoophq";
        port = 55000;
        ca = caFile;
        usernameFile = "${pki}/api-wui-username";
        passwordFile = config.sops.secrets.wazuh_api_wui_pass.path;
        # run_as needs a matching authorization context on the manager side;
        # without it the dashboard authenticates as wazuh-wui itself.
        runAs = false;
      }
    ];
  };

  # ------------------------------------------------------- retention (30 day) --
  systemd.services.wazuh-indexer-retention = {
    description = "Apply the Wazuh index retention policy (30 days)";
    wantedBy = [ "multi-user.target" ];
    after = [ "wazuh-indexer-security.service" ];
    # wants, not requires: a failure to install the policy must not take the
    # indexer down with it. Restart=on-failure below retries instead.
    wants = [ "wazuh-indexer-security.service" ];
    path = [
      pkgs.curl
      pkgs.jq
      pkgs.coreutils
    ];
    unitConfig.StartLimitIntervalSec = 0;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = 60;
    };
    script = ''
      set -euo pipefail

      api=https://hoophq:9200
      id=${retentionId}

      # Certificate auth, not a password: admin.distinguishedNames above is
      # plugins.security.authcz.admin_dn, so this certificate is a superuser by
      # DN. That keeps the admin password out of the process arguments
      # entirely, which -u would not.
      ic() {
        curl --silent --show-error \
          --cacert ${caFile} \
          --cert ${pki}/admin.pem --key ${pki}/admin-key.pem \
          "$@"
      }

      # wazuh-indexer-security.service returning does not mean the cluster will
      # answer a write. Wait for it, bounded, and let Restart handle a genuinely
      # dead indexer rather than hanging this unit forever.
      ok=no
      for _ in $(seq 1 60); do
        if ic --fail "$api/_cluster/health?wait_for_status=yellow&timeout=5s" \
             >/dev/null 2>&1; then
          ok=yes
          break
        fi
        sleep 5
      done
      if [ "$ok" != yes ]; then
        echo "indexer did not become ready; will retry" >&2
        exit 1
      fi

      # A plain PUT over an existing policy is a 409. Read the current version
      # first and pass its concurrency tokens back, so this unit is a no-op on
      # every boot after the first and still picks up an edited policy.
      cur=$(ic --fail "$api/_plugins/_ism/policies/$id" 2>/dev/null || true)
      if [ -n "$cur" ]; then
        seq_no=$(printf '%s' "$cur" | jq -r '._seq_no')
        primary=$(printf '%s' "$cur" | jq -r '._primary_term')
        url="$api/_plugins/_ism/policies/$id?if_seq_no=$seq_no&if_primary_term=$primary"
      else
        url="$api/_plugins/_ism/policies/$id"
      fi

      ic --fail -X PUT "$url" \
        -H 'Content-Type: application/json' \
        --data-binary @${retentionPolicy} > /dev/null
      echo "retention policy $id installed"

      # ism_template only binds indices created after the policy exists. Attach
      # it to anything already on disk. Expected to report failures for indices
      # that are already managed, so this is explicitly not --fail and not
      # fatal.
      for pattern in 'wazuh-alerts-*' 'wazuh-archives-*' 'wazuh-monitoring-*' 'wazuh-statistics-*'; do
        ic -X POST "$api/_plugins/_ism/add/$pattern" \
          -H 'Content-Type: application/json' \
          -d "{\"policy_id\":\"$id\"}" || true
        echo
      done
    '';
  };

  # ---------------------------------------------------------------- ordering --
  systemd.services = {
    # The dashboard binds tsAddr, which does not exist until tailscaled has
    # brought the interface up, so a cold boot would otherwise race it. Reuse
    # the oneshot that containers.nix already defines and that pihole and Home
    # Assistant already depend on, rather than polling again here.
    #
    # Deliberately wants+after and not requires: a down tailscaled should mean
    # "retry", not "blocked".
    #
    # StartLimitIntervalSec = 0 is the load-bearing line. The module already
    # sets Restart = on-failure with RestartSec = 5 (wazuh-dashboard/
    # default.nix:127), so the backoff is handled -- do NOT also set RestartSec
    # here, it conflicts rather than merging. What the module does not set is
    # the start-limit window, so without this systemd would give up on the unit
    # after five quick failures and leave the dashboard down until someone
    # noticed. On this box a tsAddr-bound unit has previously logged 2.4
    # million restarts in six days, which is the opposite failure and the
    # reason the backoff matters; both halves are needed.
    wazuh-dashboard = {
      after = [
        "tailscale-addr-online.service"
        "wazuh-indexer.service"
      ];
      wants = [ "tailscale-addr-online.service" ];
      unitConfig.StartLimitIntervalSec = 0;
    };

    # The three modules know nothing about each other, so the manager would
    # otherwise start its filebeat against an indexer that is still opening its
    # JVM. filebeat retries by itself, so this only buys a quiet boot -- but a
    # quiet boot is what makes `systemctl --failed` worth reading.
    wazuh-filebeat = {
      after = [ "wazuh-indexer.service" ];
      wants = [ "wazuh-indexer.service" ];
    };

    # Same reasoning for the API's indexer-backed calls.
    wazuh-apid.after = [ "wazuh-indexer.service" ];
  };

  # ---------------------------------------------------------------- firewall --
  #
  # tailscale0 ONLY. 9200 and 9300 are absent on purpose: the indexer is
  # loopback-bound and only the manager and the dashboard on this same host
  # talk to it.
  #
  #   1514  remoted, agent events
  #   1515  authd, agent enrollment
  #   5601  dashboard UI
  #   55000 manager API
  #
  # Port ledger: the running list lives in comments in pihole.nix and
  # homeassistant.nix. 1514/1515/1516, 5601, 9200/9300 and 55000 were all free
  # when this went in. NOT yet added to those two comment blocks -- both files
  # had uncommitted changes at the time and mixing an unrelated edit into them
  # would have muddied that work. Add these four there when next touching them.
  #
  # Note that wazuh-remoted and wazuh-authd bind the wildcard regardless of
  # what is configured -- remote.listeners has no bind-address attribute, only
  # connection/port/protocol/queueSize/allowedIps -- so this firewall scoping
  # is the actual control, not a second layer. Verify with:
  #   ss -Hltn 'sport = :1514'
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
    1514
    1515
    5601
    55000
  ];
}
