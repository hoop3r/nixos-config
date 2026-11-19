{ config, pkgs, lib, ... }:

# Home automation, served from this host.
#
# Design notes / why it looks like this:
#
#   * Native services.home-assistant, NOT a container. Two reasons, and the
#     second is the one that actually forces it:
#       - config lives in Nix here rather than in a mutable volume, which is
#         the whole point of this repo.
#       - Home Assistant finds Wi-Fi devices (Chromecast, Sonos, HomeKit-based
#         plugs and thermostats) by multicast discovery -- mDNS on
#         224.0.0.251:5353 and SSDP on 239.255.255.250:1900. A container on a
#         podman bridge cannot see either, because multicast does not cross the
#         bridge. The container route would need --network=host anyway, at
#         which point the only thing it buys over the native module is a
#         mutable config directory.
#     What this costs: no Supervisor, so no HA "add-on store". Add-ons require
#     HAOS or a Supervised install. Everything in the add-on catalogue that
#     matters here has a nixpkgs module instead (zigbee2mqtt, zwave-js,
#     esphome, matter-server, mosquitto) -- wire those up directly if needed.
#
#   * extraComponents below is LOAD-BEARING, and this is the one thing about
#     the native module that surprises people. The hass package is built with
#     exactly the Python dependencies of the components listed there. Adding an
#     integration through the web UI does NOT work if its component is absent:
#     upstream HA would pip-install the dependency at runtime, but the store is
#     read-only, so it fails. "Add Integration" in the UI is therefore a
#     two-step operation on this host:
#         1. add the component name to extraComponents
#         2. nixos-rebuild switch, THEN add it in the UI
#     HOW TO VERIFY a component's dependency actually shipped, which is less
#     obvious than it looks: do NOT inspect the package or its closure. In this
#     nixpkgs, extraComponents feeds passthru.pythonPath rather than the
#     derivation (pkgs/servers/home-assistant/default.nix, "pythonPath =
#     makePythonPath (componentBuildInputs ++ extraBuildInputs)"), so the
#     home-assistant store path is BYTE-IDENTICAL whether you list components
#     or not, and `nix-store -qR` on it shows no integration libraries at all.
#     That looks exactly like a broken override and is not one. The dependency
#     is injected through the unit's PYTHONPATH, so the real check is:
#         systemctl show home-assistant -p Environment | grep -o -- '-aiolifx-[0-9.]*'
#     Corresponding runtime symptom when it is genuinely missing is
#     "No module named 'aiolifx'" in the journal, surfacing in the UI as
#     "Invalid handler specified".
#
#     The component name is the last path segment of its docs URL --
#     https://www.home-assistant.io/integrations/sonos/ -> "sonos". The name is
#     validated at eval time against the package's component list, so a typo is
#     a build error rather than a runtime surprise.
#
#   * Bound tailnet-only, mirroring the *arr UIs in containers.nix and the
#     Pi-hole dashboard in pihole.nix: http.server_host is 127.0.0.1 plus the
#     tailnet address, never 0.0.0.0, and 8123 is opened on tailscale0 only.
#     There is still deliberately no nginx vhost and no ACME certificate --
#     see the note at the bottom before adding one.
#
#     BUT this is no longer the same thing as "not reachable from the
#     internet". tailscale.nix publishes 8123 over Tailscale Funnel, so
#     https://hoophq.tail072ce1.ts.net/ is PUBLIC and HA's own login is the
#     only thing in front of it. Funnel does not need an open firewall port --
#     tailscaled accepts the connection over the tunnel it already holds and
#     proxies to 127.0.0.1:8123 -- which is exactly why nothing in the
#     networking.firewall block below mentions it. Enable MFA on every HA
#     account, and read the use_x_forwarded_for comment in the http block.
#
#   * The unit orders after tailscale-addr-online.service. This is not
#     decorative. http.server_host is an explicit bind list, and tailscale0
#     gets 100.124.247.94 asynchronously after the interface appears, so
#     starting earlier means aiohttp tries to bind an address that does not
#     exist yet and Home Assistant exits. pihole.nix documents what that class
#     of bug costs when the process happens to survive it instead; here it is a
#     clean failure, but a failure either way. The readiness oneshot is the one
#     already defined in containers.nix -- reused, not duplicated.
#
#   * openFirewall and openFirewallForComponents stay false, for the reason
#     spelled out at length in pihole.nix and forensics.nix: those options
#     write global networking.firewall.allowedTCPPorts/allowedUDPPorts, and a
#     global accept sits earlier in the chain than any interface-scoped rule,
#     so the scoped rule never matches a packet. Ports are opened per-interface
#     at the bottom of this file instead.

let
  lanIface = "wlp0s20f3";

  # Same hardcoded tailnet v4 as containers.nix and pihole.nix.
  tsAddr = "100.124.247.94";

  # 8123 is HA's default and is clear on this box. Taken: 22, 80, 443 (nginx),
  # 6881 (gluetun), 7878 (radarr), 8080 (qbittorrent), 8089 (pihole-web),
  # 8191 (byparr), 8989 (sonarr), 9000 (authentik), 9696 (prowlarr), 25565,
  # 32400/32401/32600 (plex).
  haPort = 8123;
in
{

  services.home-assistant = {
    enable = true;

    # See the header note before editing this list -- adding an integration in
    # the UI requires adding it here first.
    #
    # Note this REPLACES the module's default list rather than extending it, so
    # default_config and met are repeated here on purpose: onboarding does not
    # complete without them.
    extraComponents = [
      # --- required for onboarding / the base install -------------------------
      "default_config" # the standard bundle: zeroconf, ssdp, dhcp, bluetooth,
                       # mobile_app, cloud, recorder, history, logbook, sun,
                       # person, backup, webhook, stream, energy, ...
      "met"            # weather provider the onboarding wizard offers
      "radio_browser"  # onboarding offers this too; absent it logs an error
      "isal"           # C zlib/websocket acceleration for the frontend

      # --- Wi-Fi / LAN devices ------------------------------------------------
      #
      # The four below were added 2026-11-08 because HA's own discovery was
      # already finding these devices and logging "Error occurred loading flow
      # for integration <x>" on a loop -- 41 apple_tv, 30 xbox and 14 vizio
      # attempts in two hours. Discovery finds a device, tries to offer its
      # config flow, and fails on the missing dependency. None of them need a
      # firewall port: HA connects outbound and the replies are conntrack
      # matches, unlike the LIFX/Govee broadcast cases below.
      "vizio"              # the TV at 192.168.1.5. Pairs with an on-screen PIN
      "apple_tv"           # pyatv. Pairs with an on-screen code
      "xbox"               # 192.168.1.212. NOTE this one is cloud-based and
                           # needs an Azure AD application credential you
                           # register yourself -- it will not work on the
                           # rebuild alone
      "govee_ble"          # Govee over Bluetooth. Added to stop the repeated
                           # flow error, which gets WORSE now that BlueZ is on
                           # (below) and HA sees more adverts: the H6046
                           # advertises a "Govee*" local name, which matches
                           # this integration. It will NOT give a second way to
                           # control the light -- govee_ble ships only
                           # sensor/binary_sensor/event platforms, no light
                           # platform. It is the right component for Govee
                           # thermometers and hygrometers if any ever arrive.

      "cast"               # Chromecast / Google TV / Nest Hub
      "sonos"
      "roku"
      "androidtv_remote"   # Android TV / Google TV remote control
      "homekit_controller" # many Wi-Fi plugs, bulbs and thermostats speak
                           # HomeKit locally; this is often the best way to use
                           # them without the vendor cloud
      "govee_light_local"  # Govee over the LAN (192.168.1.4). Requires udp/4002
                           # open below -- without it every scan silently goes
                           # unanswered even though the device is healthy.
                           # LAN Control is confirmed on and the device's
                           # 4001/4003 confirmed listening; see the Govee note
                           # at the bottom of this file.
      "hue"
      "lifx"               # 5 bulbs on the LAN as of 2026-11-08. NOTE: this
                           # component alone is not enough -- LIFX discovery is
                           # UDP broadcast and needs the firewall rule below.
                           # See the LIFX note at the bottom of this file.
      "tplink"             # Kasa / Tapo plugs and bulbs
      "shelly"
      "wiz"

      # --- this host's own homelab --------------------------------------------
      #
      # Every one of these is CONFIG-FLOW ONLY: they cannot be configured in
      # YAML, so listing them here makes the flow loadable and nothing more.
      # Each still has to be added once in Settings -> Devices & Services, and
      # most want a credential (see the homelab note at the bottom of this
      # file for where each key lives). Nothing below needs a firewall port --
      # these all talk to 127.0.0.1 on this same box.
      "systemmonitor"      # hoophq's own CPU / RAM / disk / load / temps.
                           # The only one needing no credential at all.
      "plex"               # 32400
      "radarr"             # 7878
      "sonarr"             # 8989
      "qbittorrent"        # 8080 (published by gluetun, not qbittorrent)
      "pi_hole"            # 8089. Verified this HA speaks Pi-hole's v6 API
                           # (determine_api_version / api_by_version in
                           # pi_hole/config_flow.py, hole==0.9.0) -- older HA
                           # only did v5, which FTL 6.x no longer serves.
                           # pihole.nix sets no password, so the flow should
                           # accept an empty one.
      "tailscale"          # needs a Tailscale API key, which this host did
                           # NOT previously have -- pihole.nix notes there is
                           # no Tailscale credential in hosts/hoophq/secrets.
                           # Create one at
                           # https://login.tailscale.com/admin/settings/keys
      "rest"               # generic REST sensors, for the three services
                           # below that have no core integration at all

      # --- HomeKit, BOTH directions (they are different integrations) ---------
      #
      # homekit_controller (listed above, under Wi-Fi/LAN devices) pulls a
      # HomeKit accessory INTO HA. "HomeKit Device" in the UI.
      #
      # homekit, here, is the opposite: a HAP bridge that exposes HA entities
      # OUT to the Apple Home app. "HomeKit Bridge" in the UI. Added
      # 2026-11-11 after it failed in the UI with
      #   Error occurred loading flow for integration homekit:
      #   No module named 'pyhap'
      # which is the same missing-component signature as the LIFX case in the
      # bottom note. Verified the dep shipped, and note the NAME MISMATCH that
      # makes the usual PYTHONPATH check miss it: the module is `pyhap`, the
      # nixpkgs package is `hap-python` (5.0.0, plus homekit-audio-proxy).
      # Grepping PYTHONPATH for "pyhap" gives a false negative -- same trap as
      # matter-python-client vs python-matter-server. Needs tcp/21063
      # open on the LAN too; see the firewall block.
      "homekit"

      # --- Matter -------------------------------------------------------------
      #
      # The component is only the HA-side client; it is useless on its own. It
      # speaks websocket to services.matter-server (enabled below), which is
      # the thing that actually holds the Matter fabric and its commissioning
      # credentials. Both halves are required -- see the Matter note at the
      # bottom of this file for the commissioning paths and their limits.
      "matter"
      # "thread"  / "otbr" -- both exist in this hass package, but they are for
      #           a Thread border router. No Thread radio is attached (still no
      #           /dev/ttyUSB*, /dev/ttyACM* or /dev/serial/by-id as of
      #           2026-11-11), so they would have nothing to drive.

      # --- common additions, uncomment as needed ------------------------------
      # Each one is a rebuild, not a UI-only change.
      # "esphome"        # DIY ESP32/ESP8266 sensors (see also services.esphome)
      # "mqtt"           # needs a broker -- services.mosquitto
      # "nest"           # Nest thermostats; also needs a Google Cloud project
      # "ecobee"
      # "honeywell"
      # "spotify"
      # "plex"           # this host already runs Plex, on 32400
    ];

    # http.server_host is the access control, so these must stay false --
    # see the header note.
    openFirewall = false;
    openFirewallForComponents = false;

    config = {
      # Pulls in the standard integration bundle. Must be paired with
      # "default_config" in extraComponents above: this line enables it, that
      # line is what puts its Python dependencies in the closure.
      default_config = { };

      homeassistant = {
        name = "hoophq";

        # time_zone is deliberately not set -- the module defaults it to
        # config.time.timeZone, which configuration.nix already pins to
        # America/New_York. Setting it twice is just a second place to forget.
        #
        # latitude/longitude/elevation/unit_system are deliberately NOT set
        # either. Anything named here in configuration.yaml becomes read-only
        # in the UI, and these are exactly the values the onboarding wizard
        # asks for and stores in .storage/core.config. Leave them to onboarding
        # unless you want them pinned in Nix.
      };

      http = {
        server_port = haPort;

        # Loopback plus the tailnet address, never 0.0.0.0. Loopback is kept
        # for local verification (`curl -sI http://127.0.0.1:8123/`) without
        # needing the tailnet to be up.
        #
        # This is an explicit bind list, which is why the unit below waits for
        # the tailnet address. See the header note.
        server_host = [
          "127.0.0.1"
          tsAddr
        ];

        # Required because tailscaled proxies Funnel traffic into this port --
        # see the funnel unit in tailscale.nix. Funnel terminates TLS inside
        # tailscaled and forwards to 127.0.0.1:8123, so without these every
        # request from the internet is attributed to LOOPBACK. That is not
        # cosmetic: HA's login-attempt tracking and ip_ban key on the client
        # address, so a stranger failing passwords on the public URL would get
        # 127.0.0.1 banned and lock out local verification.
        #
        # trusted_proxies is loopback ONLY, and that is what makes this safe to
        # enable while 8123 is still directly bound on the tailnet -- which the
        # header note above warns about. HA honours X-Forwarded-For only when
        # the PEER is a trusted proxy: a tailnet client that sets the header
        # itself connects from 100.x, is not trusted, and gets a 400 rather
        # than a spoofed source address. Do NOT add tsAddr or a LAN range here,
        # and do not open 8123 on lanIface while this is on.
        use_x_forwarded_for = true;
        trusted_proxies = [ "127.0.0.1" ];
      };

      # Bound the SQLite recorder database the same way queryLogDeleter bounds
      # the FTL one in pihole.nix. HA's default is to keep 10 days; 30 is more
      # useful for month-over-month energy history and is still only tens of MB
      # for a handful of devices. Raise it knowingly -- this database grows
      # with (devices x polling frequency x days).
      recorder.purge_keep_days = 30;

      # Prowlarr, Bazarr and Authentik have NO core Home Assistant
      # integration, so they come in as generic REST sensors instead. Those
      # are YAML-configurable, which is why these three can live in Nix while
      # everything in extraComponents above cannot.
      #
      # The API keys come from !secret, resolved out of
      # /var/lib/hass/secrets.yaml -- generated at boot by the
      # hass-secrets.service unit below. Read that unit's comment before
      # changing anything here: the keys are deliberately NOT in this file and
      # NOT in the nix store.
      #
      # A failed fetch makes the entity `unavailable` rather than killing the
      # platform, so these double as up/down indicators -- a failed one shows
      # as `unavailable` in Developer Tools -> States rather than vanishing.
      sensor = [
        {
          platform = "rest";
          name = "Prowlarr";
          unique_id = "hoophq_prowlarr";
          resource = "http://127.0.0.1:9696/api/v1/system/status";
          headers."X-Api-Key" = "!secret prowlarr_api_key";
          value_template = "{{ value_json.version }}";
          json_attributes = [ "appName" "version" "runtimeVersion" "isDocker" ];
          scan_interval = 300;
        }
        {
          platform = "rest";
          name = "Bazarr";
          unique_id = "hoophq_bazarr";
          resource = "http://127.0.0.1:6767/api/system/status";
          headers."X-API-KEY" = "!secret bazarr_api_key";
          value_template = "{{ value_json.data.bazarr_version }}";
          scan_interval = 300;
        }
        {
          # Stays `unavailable` until a token exists -- see hass-secrets below.
          platform = "rest";
          name = "Authentik";
          unique_id = "hoophq_authentik";
          resource = "http://127.0.0.1:9000/api/v3/admin/version/";
          headers.Authorization = "!secret authentik_token_header";
          value_template = "{{ value_json.version_current }}";
          json_attributes = [ "version_current" "version_latest" "outdated" ];
          scan_interval = 900;
        }
      ];

      # Keep automations, scripts and scenes editable in the UI while the rest
      # of configuration.yaml stays declarative.
      #
      # HA merges config keys of the form "<domain> <label>", so these three
      # coexist with any future Nix-defined automations under
      # "automation manual". The module's YAML writer unquotes leading-"!"
      # strings, so these land as real !include directives.
      #
      # Why not configWritable: that option makes configuration.yaml itself
      # writable, but the module rewrites it from the store on every start, so
      # UI edits to it are silently discarded. The include files below are
      # outside that file and therefore actually persist.
      #
      # These three files MUST exist before HA starts or the !include is a
      # startup error -- hence the tmpfiles rules below.
      "automation ui" = "!include automations.yaml";
      "script ui" = "!include scripts.yaml";
      "scene ui" = "!include scenes.yaml";
    };
  };

  # Bluetooth, enabled for Home Assistant's sake rather than the laptop's --
  # which is why it lives in this file and not configuration.nix.
  #
  # default_config pulls in HA's bluetooth integration, and HA then finds hci0
  # at the kernel level. But NixOS was never told to run BlueZ here
  # (bluetooth.service was literally "not-found"), so habluetooth had an
  # adapter with no daemon behind it and logged
  #   hci0: Failed to force stop scanner: 'NoneType' object has no attribute 'send'
  # about 14 times a minute -- 36 errors in the first two and a half minutes
  # after a restart. Harmless in itself, but it buries anything real in the
  # journal.
  #
  # Enabling the daemon is the fix that leaves the integration working rather
  # than merely quiet. The alternative was deleting HA's Bluetooth config entry
  # in the UI, which is .storage state with no declarative counterpart and which
  # default_config may simply re-offer. This also makes govee_ble above
  # functional, and is the prerequisite for any future BLE sensor.
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  # The Matter fabric controller, which is what makes "add device by pairing
  # code" possible. Lives in this file rather than configuration.nix for the
  # same reason hardware.bluetooth above does: it exists only to serve HA.
  #
  # Two processes, one integration. The "matter" component in extraComponents
  # is just a websocket client; this service holds the fabric, the commissioned
  # device credentials and the Matter certificate store in
  # /var/lib/matter-server. Losing that directory means re-commissioning every
  # device, so it is the one piece of HA state here that genuinely wants a
  # backup -- unlike the recorder DB, it cannot be regenerated.
  #
  # openFirewall stays false, and for ONCE that is not the usual global-accept
  # argument: this module's openFirewall only ever opens tcp/5580, which is
  # the websocket API that HA consumes over loopback. It opens nothing Matter
  # actually speaks on the wire. So false is both correct and free -- the real
  # Matter port is handled in the firewall block below.
  #
  # ordering: the module already sets `before = [ "home-assistant.service" ]`
  # and `after = [ "network-online.target" ]`, so nothing extra is needed here.
  # Note it does NOT wait for tailscale0 -- it does not have to, because unlike
  # HA it binds no explicit address.
  services.matter-server = {
    enable = true;
    openFirewall = false;
  };

  # Pre-create the UI-managed include files as empty YAML lists. tmpfiles only
  # writes the argument when it creates the file, so this seeds them once and
  # never clobbers what the UI editor writes afterwards.
  #
  # configDir defaults to /var/lib/hass; the module's own tmpfiles rule creates
  # the directory itself.
  systemd.tmpfiles.rules = [
    "f /var/lib/hass/automations.yaml 0640 hass hass - []"
    "f /var/lib/hass/scripts.yaml 0640 hass hass - []"
    "f /var/lib/hass/scenes.yaml 0640 hass hass - []"
  ];

  # Home Assistant's secrets.yaml, rendered at boot from credentials that
  # ALREADY exist on this box, rather than from a new secret of our own.
  #
  # Why not sops, given the rest of this repo uses it: the Prowlarr and Bazarr
  # keys are not secrets we get to choose. They are generated by those
  # services and live in their own config files, so putting copies in
  # hosts/hoophq/secrets would create a second source of truth that goes stale
  # silently the moment either key is rotated from its own UI. Reading them at
  # boot instead means rotation needs no rebuild and no re-encryption.
  #
  # Why not just put them in homeassistant.nix: settings render into a
  # world-readable /nix/store path. Same reason pihole.nix refuses to set a
  # dashboard password. Nothing here ever touches the store.
  #
  # Result is 0400 hass:hass, written via a temp file and renamed so HA never
  # sees a half-written secrets.yaml. Values are always emitted even when a
  # source file is missing, because a MISSING key is a hard HA startup error
  # ("Secret prowlarr_api_key not found") whereas an empty one just makes that
  # one sensor unavailable, which is visible in Developer Tools -> States.
  #
  # Authentik is the one that needs a human: it has no key sitting on disk, so
  # create a token in its UI (Directory -> Tokens, or an admin API token) and
  # drop it in as a single line:
  #     sudo install -o hass -g hass -m 0400 /dev/stdin \
  #       /var/lib/hass/authentik.token <<< 'THE_TOKEN'
  #     sudo systemctl restart hass-secrets home-assistant
  # Until then the Authentik sensor simply reads `unavailable`.
  #
  # Deliberately `wantedBy` rather than `requiredBy`: if this ever fails, Home
  # Assistant should still come up with whatever secrets.yaml it already had.
  systemd.services.hass-secrets = {
    description = "Render Home Assistant secrets.yaml from on-disk service credentials";
    wantedBy = [ "home-assistant.service" ];
    before = [ "home-assistant.service" ];
    after = [ "systemd-tmpfiles-setup.service" ];
    path = [ pkgs.coreutils pkgs.gnused pkgs.gawk ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -u
      cfg=/home/bugbyte/podman/mediastack/data/config
      out=/var/lib/hass/secrets.yaml

      prowlarr=""
      if [ -r "$cfg/prowlarr/config.xml" ]; then
        prowlarr=$(sed -n 's:.*<ApiKey>\(.*\)</ApiKey>.*:\1:p' "$cfg/prowlarr/config.xml" | head -1)
      fi

      # Bazarr's config.yaml holds several `apikey:` lines -- the indexer and
      # provider sections have their own. Only the one inside the top-level
      # `auth:` block is Bazarr's own API key, so scope the match to that
      # block instead of taking the first hit.
      bazarr=""
      if [ -r "$cfg/bazarr/config/config.yaml" ]; then
        bazarr=$(awk '/^auth:/{a=1;next} /^[^[:space:]]/{a=0} a && $1=="apikey:"{print $2; exit}' \
                 "$cfg/bazarr/config/config.yaml")
      fi

      authentik=""
      if [ -r /var/lib/hass/authentik.token ]; then
        authentik=$(tr -d '\r\n' < /var/lib/hass/authentik.token)
      fi

      umask 077
      tmp=$(mktemp /var/lib/hass/.secrets.yaml.XXXXXX)
      {
        printf 'prowlarr_api_key: "%s"\n' "$prowlarr"
        printf 'bazarr_api_key: "%s"\n' "$bazarr"
        printf 'authentik_token_header: "Bearer %s"\n' "$authentik"
      } > "$tmp"
      chown hass:hass "$tmp"
      chmod 0400 "$tmp"
      mv -f "$tmp" "$out"
    '';
  };

  # Reuse the readiness oneshot from containers.nix rather than adding a second
  # poller for the same address. Without this, http.server_host's tailnet entry
  # is unbindable at boot and HA exits -- see the header note.
  systemd.services.home-assistant = {
    after = [ "tailscale-addr-online.service" ];
    wants = [ "tailscale-addr-online.service" ];
  };

  # Interface-scoped on purpose; see the header note on openFirewall. These
  # merge with the port lists pihole.nix contributes for the same two
  # interfaces -- NixOS concatenates them, it does not overwrite.
  networking.firewall.interfaces = {
    # The UI, reachable over the tailnet only. Note 8123 is deliberately NOT
    # opened on lanIface: a LAN client that should reach HA belongs on the
    # tailnet, which works on the home wifi as well as off it.
    "tailscale0".allowedTCPPorts = [ haPort ];

    ${lanIface} = {
      # Discovery, inbound on the LAN. Both are genuinely required rather than
      # covered by the default established/related accept:
      #   5353 -- mDNS/zeroconf. Responses go to the multicast group
      #           224.0.0.251:5353, not back to the query's source port, so
      #           conntrack never sees them as a reply.
      #   1900 -- SSDP/UPnP. Unicast M-SEARCH answers are conntracked, but the
      #           NOTIFY announcements devices broadcast to 239.255.255.250
      #           are not, and those are how a device that appears later gets
      #           noticed.
      #   4002 -- Govee local API. govee-local-api sends its scan to
      #           239.255.255.250:4001 but LISTENS on a fixed udp/4002
      #           (LISTENING_PORT in govee_local_api/controller.py), so unlike
      #           LIFX this is an ordinary port rule rather than a --sport
      #           match. Bulbs answer unicast to :4002, which is not a
      #           conntrack match for the same reason LIFX's replies are not.
      #   5540 -- Matter. The registered Matter/CHIP UDP port, and the
      #           controller binds it locally rather than only dialing out to
      #           it, so inbound is required for operational traffic and for
      #           commissioning over IP. NOTE this rule matters for IPv6 far
      #           more than IPv4: Matter operational traffic is IPv6-ONLY.
      #           NixOS writes allowedUDPPorts into both iptables and
      #           ip6tables, so one entry covers both -- but that also means
      #           the v6 half silently does nothing if networking.enableIPv6
      #           is ever turned off, which would break Matter entirely rather
      #           than degrade it. (Confirmed 2026-11-11: enableIPv6 is true
      #           and wlp0s20f3 holds a global 2600:1700:8870:e4c0::/64 address
      #           with an RA default route, so the prerequisite is met.)
      #           mDNS on 5353 above is also load-bearing for Matter -- that
      #           is how `_matterc._udp` (commissionable) and `_matter._tcp`
      #           (operational) devices are found at all.
      # Without these, HA starts fine and simply never discovers anything,
      # which is an annoying thing to debug.
      allowedUDPPorts = [ 5353 1900 4002 5540 ];

      # Sonos delivers UPnP event callbacks TO this host on tcp/1400, so it
      # has to be reachable inbound or Sonos entities go unavailable after the
      # subscription expires. The module would open this itself via
      # openFirewallForComponents -- 1400 for sonos is in fact the ONLY port
      # that option knows about -- but it writes a global
      # networking.firewall.allowedTCPPorts, which is exactly what the header
      # note rules out. Scoped here instead.
      # https://www.home-assistant.io/integrations/sonos/#network-requirements
      #
      # 21063 -- the HomeKit BRIDGE (the "homekit" component), which unlike
      #          everything else in this file is a genuine inbound LISTENER.
      #          HA advertises the bridge over mDNS and Apple devices then
      #          connect TO it on tcp/21063 (DEFAULT_PORT in
      #          components/homekit/const.py), so without this rule the bridge
      #          shows up in the Home app and then fails to add -- the usual
      #          silent-discovery failure, just in the other direction.
      #          If a SECOND bridge is ever created in the UI it takes 21064,
      #          and so on upward; add ports here as needed rather than
      #          guessing a range.
      allowedTCPPorts = [ 1400 21063 ];
    };
  };

  # LIFX discovery, which needs a source-port match and therefore cannot be
  # expressed with networking.firewall.interfaces.
  #
  # aiolifx broadcasts a GetService to 255.255.255.255:56700 (and to the
  # subnet broadcast) from an EPHEMERAL local port -- LifxDiscovery.start()
  # defaults to listen_port=0 and HA's lifx/discovery.py calls it with no
  # arguments. Bulbs then answer from their own port 56700 to that random
  # port. There is no fixed destination port to open, which is why this is a
  # --sport rule rather than an allowedUDPPorts entry.
  #
  # The default established/related accept does NOT cover these replies. The
  # conntrack entry created by the outbound packet has dst=255.255.255.255,
  # so an answer arriving from 192.168.1.x does not match it and is treated as
  # a new inbound connection. Measured on 2026-11-08, before this rule:
  #   unicast  GetService -> 192.168.1.6      -> reply received (conntrack hit)
  #   broadcast GetService, fresh local port  -> ZERO replies from any of the
  #                                              five bulbs
  #   broadcast GetService, port already used for a unicast to .6
  #                                           -> replies from .6 only, because
  #                                              only .6 had a conntrack entry
  # That last case is the tell: it is per-peer conntrack state, not a routing
  # or bulb problem.
  #
  # Scoped to the LAN subnet and the LAN interface. The cost of this rule,
  # stated plainly: any host on 192.168.1.0/24 may send UDP from source port
  # 56700 to any UDP port on this box, including HA's ephemeral sockets. That
  # is inherent to broadcast discovery protocols -- the alternative is opening
  # the whole ephemeral range, which is worse.
  #
  # Appended to nixos-fw rather than inserted into INPUT (which is what
  # webserver.nix does for its Cloudflare DROPs) because the firewall service
  # flushes and rebuilds nixos-fw on every start, so this rule cannot
  # accumulate duplicates across reloads.
  networking.firewall.extraCommands = ''
    iptables -A nixos-fw -i ${lanIface} -s 192.168.1.0/24 \
             -p udp --sport 56700 -j nixos-fw-accept
  '';
}

# =============================================================================
# REACHING IT, AND WHAT IS DELIBERATELY NOT SET UP
# =============================================================================
#
#   Over the tailnet:   http://100.124.247.94:8123/
#   Or an ssh tunnel:   ssh -L 8123:127.0.0.1:8123 bugbyte@hoophq
#                       then http://127.0.0.1:8123/
#
#   First run is an onboarding wizard: it creates the owner account and asks
#   for the location that latitude/longitude were deliberately left out of
#   above. The HA companion app takes the same tailnet URL as its server
#   address and keeps working off-network, which is the entire reason this is
#   tailnet-only.
#
# -- No public vhost (chosen, not overlooked) ---------------------------------
#   webserver.nix could publish this as hass.hoop3r.com in a few lines, the way
#   plex.hoop3r.com is published. It is not, and two things need deciding
#   before it is:
#
#     * http.use_x_forwarded_for + http.trusted_proxies = [ "127.0.0.1" ]
#       become mandatory in the same change. HA rejects proxied requests
#       without them. They are also why that change must not land while 8123
#       is directly reachable from the same network as a client: with
#       use_x_forwarded_for on, anything that can reach the port directly can
#       claim any source IP via the header.
#
#     * Authentik forward-auth is the obvious instinct and is a poor fit here.
#       The snippet in webserver.nix works for browsers, but the HA companion
#       app and HA webhooks (which is how most automations get triggered from
#       outside) cannot complete an interactive Authentik login. Protecting it
#       that way ends up needing bypass rules for /api/ and /auth/ wide enough
#       that the forward-auth is close to decorative. HA's own auth, with MFA
#       enabled and Cloudflare in front, is the more honest configuration.
#
#   Cloudflare Flexible SSL applies if a vhost is ever added: $scheme is always
#   "http" behind it, so any redirect or proxy_set_header must hardcode https.
#
# -- No Zigbee or Z-Wave radio (Matter IS now enabled -- see the next note) ---
#   Nothing Zigbee, Z-Wave or Thread is configured, because no USB
#   coordinator is attached (lsusb is empty; there is no /dev/ttyUSB*,
#   /dev/ttyACM* or /dev/serial/by-id). When one arrives, the shape is:
#
#     * Zigbee -- services.zigbee2mqtt + services.mosquitto, or ZHA inside HA
#       by adding "zha" to extraComponents. Reference the stick by its
#       /dev/serial/by-id/... path, never /dev/ttyUSB0: that number is
#       assigned in probe order and moves when anything else USB is plugged in.
#     * Z-Wave -- services.zwave-js (or zwave-js-ui), same by-id rule.
#     * Thread -- services.openthread-border-router, to carry Matter-over-
#       Thread devices. matter-server itself is already on and needs no radio;
#       only Thread does. Wants a Thread-capable radio plus IPv6 on the LAN.
#
#   All four modules are present in this nixpkgs. matter-server is now ENABLED
#   (next note); zigbee2mqtt, zwave-js and openthread-border-router are not.
#
# -- Matter: enabled 2026-11-11, and which pairing codes actually work --------
#   services.matter-server is on and "matter" is in extraComponents, so the
#   two-step rule applies as usual: rebuild first, THEN add Matter in
#   Settings -> Devices & Services. It is config-flow only; the flow should
#   accept the default websocket URL ws://localhost:5580/ws.
#
#   Client/server schema compat, VERIFIED at this nixpkgs rev rather than
#   assumed -- it is the other thing that makes the flow fail outright, with
#   "Matter schema version is incompatible":
#     HA side  matter-python-client 0.6.8   SCHEMA_VERSION     = 11
#     server   python-matter-server 8.1.2   SCHEMA_VERSION     = 11
#                                           MIN_SCHEMA_VERSION =  9
#   client/connection.py rejects on `info.schema_version < SCHEMA_VERSION` or
#   `info.min_supported_schema_version > SCHEMA_VERSION`; 11<11 and 9>11 are
#   both false, so this pair is good. Note the two halves are SEPARATE
#   packages with unrelated version numbers (8.1.2 vs 0.6.8) -- do not read
#   that gap as a mismatch, and re-check the two constants above, not the
#   package versions, after any nixpkgs bump.
#
#   Matter is IPv6-ONLY for operational traffic. That is a prerequisite, not a
#   preference, and it is the first thing to check if devices commission and
#   then go unavailable. Satisfied here by the BGW320-500's RA -- see
#   the udp/5540 comment in the firewall block above, and note that the
#   BGW320 leaking v6 via RA is the same behaviour documented as a nuisance
#   for Pi-hole. Here it is load-bearing.
#
#   TWO COMMISSIONING PATHS, and only one of them works on this box today:
#
#   1. A device ALREADY on the network / already in another ecosystem --
#      WORKS. This is the normal path for an Apple Home household: open the
#      Home app, pick the accessory, "Turn On Pairing Mode", and it issues a
#      NEW pairing code. Enter that in HA. Commissioning happens over IP via
#      mDNS, needs no Bluetooth, and the device ends up in both fabrics --
#      Matter is multi-admin, so adding it to HA does not remove it from
#      Apple Home. The code printed on the device's own label is a
#      single-use-ish manufacturer code and is NOT what you want here if the
#      device is already commissioned elsewhere.
#
#   2. A factory-new device, never commissioned -- EXPECT THIS TO FAIL from
#      the server. A new device is not on the wifi yet, so the commissioner
#      has to reach it over BLE to hand it credentials, and this nixpkgs
#      module makes that hard. The unit (see the module source) sets
#      DynamicUser, CapabilityBoundingSet = "", PrivateDevices,
#      DevicePolicy = "closed", PrivateUsers and a RestrictAddressFamilies
#      list that does NOT include AF_BLUETOOTH, and it never passes
#      --bluetooth-adapter. /run/dbus IS bind-mounted, so talking to bluetoothd
#      is not categorically blocked, but it has not been verified here and
#      BlueZ's D-Bus policy is not friendly to a DynamicUser caller.
#
#      Do NOT "fix" this by unconditionally relaxing the sandbox. The much
#      easier route is to commission with a phone, which has a working BLE
#      radio and a vendor-blessed commissioner: the HA companion app can hand
#      off to the OS commissioner, or commission it in Apple Home first and
#      then use path 1. If server-side BLE really is wanted, the shape is
#        services.matter-server.extraArgs."bluetooth-adapter" = 0;
#      plus systemd.services.matter-server.serviceConfig overrides for
#      RestrictAddressFamilies (add "AF_BLUETOOTH") and probably
#      PrivateUsers/DynamicUser -- treat it as an experiment and verify with
#      `journalctl -u matter-server`, not as a known-good config.
#
#   State lives in /var/lib/matter-server and holds the fabric's credentials.
#   It is NOT regenerable: lose it and every device needs re-commissioning.
#   Worth backing up, unlike home-assistant_v2.db.
#
#   Thread-based Matter devices (as opposed to wifi ones) still will not work:
#   they need a border router, there is no Thread radio here, and "thread" /
#   "otbr" in extraComponents would have nothing to drive. An Apple TV 4K or
#   HomePod on the LAN is itself a Thread border router, which can carry such
#   devices, but HA needs the Thread network credentials to use it -- that is
#   a separate exercise, not something this change enables.
#
# -- LIFX, and the shape of this class of bug ---------------------------------
#   Hit on 2026-11-08. Adding LIFX in the UI returned:
#       Config flow could not be loaded: {"message":"Invalid handler specified"}
#   That message means precisely one thing: HA has no config-flow handler
#   registered for the domain, i.e. the component is not in the package. It is
#   NOT a network or pairing problem, and no amount of retrying in the UI will
#   change it. The fix is the two-step in the header note -- add "lifx" to
#   extraComponents, rebuild, then add it in the UI. Treat
#   "Invalid handler specified" as a synonym for "you forgot the rebuild".
#
#   LIFX then needed a SECOND, unrelated fix, which is worth knowing about
#   because it fails silently rather than with an error: the integration would
#   load, but discovery would find nothing. The bulbs are reachable the whole
#   time -- unicast works -- but the broadcast replies that discovery depends
#   on are dropped by this host's firewall. The --sport 56700 rule above is
#   that fix; the measurements behind it are recorded there.
#
#   Diagnosing the same shape again, without root and without HA running:
#   broadcast a 36-byte LIFX GetService (type 2, tagged) from a FRESH local
#   port and see whether anything answers, then repeat from a port that has
#   already carried a unicast to one bulb. If only that one bulb answers, it
#   is conntrack, not the network. The bulbs are also easy to confirm
#   independently -- they are the D0:73:D5 OUI in `ip neigh`.
#
#   The general lesson for anything added here later: a local-push or
#   local-polling integration that finds devices by broadcast or multicast
#   needs a firewall rule as well as a component, and only the component
#   failure is loud.
#
# -- Govee: local API confirmed live; udp/4002 is the whole fix ---------------
#   Investigated 2026-11-08. The device is fine, LAN Control is on, and the
#   only thing that was ever wrong is on THIS host: the missing component plus
#   the missing udp/4002 rule above.
#
#   The device is 192.168.1.4, MAC prefix d4:ad:fc = "Shenzhen Intellirocks
#   Tech. Co. Ltd.", which is Govee's manufacturer. Govee holds no OUI under
#   its own name, so searching the IEEE list for "govee" finds nothing -- look
#   for Intellirocks. Local OUI database: hwdata's share/hwdata/oui.txt,
#   formatted "XX-XX-XX   (hex)<TAB><TAB>Org", so match the dashed uppercase
#   form.
#
#   Measured port state on the device, which is what settled it:
#       192.168.1.4:4001  open      <- Govee scan port, so LAN Control IS on
#       192.168.1.4:4002  closed    <- correct; 4002 is HA's port, not the
#                                      device's
#       192.168.1.4:4003  open      <- Govee command port
#       192.168.1.4:4099  closed    <- control port, validates the method
#   Technique, and it needs no root: connect() a UDP socket to the target and
#   send, then send again. A connected UDP socket surfaces ICMP
#   port-unreachable as ECONNREFUSED, so "closed" is positive evidence and
#   silence means something is listening. ALWAYS include a port nothing could
#   be listening on as a control -- without it, a host that simply drops ICMP
#   is indistinguishable from an open port. Cross-checked against a LIFX bulb
#   (56700 open, 4099 closed) to confirm the method works on this LAN.
#
#   CONFIRMED WORKING once udp/4002 was open. The device answered with:
#       sku H6046 (RGBIC TV light bars), wifi fw 2.06.02,
#       device 32:BA:CE:32:37:38:2D:5E
#   and -- this is the detail that explains everything above -- the two replies
#   arrived from source ports 65122 and 65123. Ephemeral, and different for
#   each packet.
#
#   That is why the obvious first probe produces a confident false negative:
#   sending a scan and waiting for a reply shows nothing even when the device
#   is perfectly healthy, because the reply lands on udp/4002 from an
#   ARBITRARY high port. It is not a conntrack match, and it cannot be covered
#   by pre-seeding entries for 4001/4002/4003. Before the udp/4002 rule above
#   exists, every scan looks unanswered. That dead end cost a wrong diagnosis
#   once already -- do not repeat it. Test reachability with the port-state
#   probe above, not with a scan-and-wait.
#
#   If Govee ever does turn out to be unreachable on a different device, the
#   two fallbacks -- neither wired up -- are services.govee2mqtt (cloud API key
#   plus services.mosquitto, which this host does not run) and "govee_ble" in
#   extraComponents (needs hardware.bluetooth.enable = true; hci0 exists but
#   bluetooth.service is inactive, and it only works in Bluetooth range).
#
# -- The homelab integrations, and where each credential comes from -----------
#   Added 2026-11-08. Split by HOW they are configured, because that decides
#   whether Nix can do anything for them at all.
#
#   CONFIG-FLOW ONLY -- listed in extraComponents, but each must be added once
#   by hand in Settings -> Devices & Services. None of these can be configured
#   in YAML, so there is nothing more this file can do for them:
#
#     systemmonitor  no credential. Pick the sensors you want in the flow
#                    (processor use, memory, disk /, load, temps).
#     plex           http://127.0.0.1:32400 — sign in, or use a claim token.
#     radarr         http://127.0.0.1:7878 — API key is in Radarr's
#                    Settings -> General, or read it from
#                    .../config/radarr/config.xml (<ApiKey>).
#     sonarr         http://127.0.0.1:8989 — same, config/sonarr/config.xml.
#     qbittorrent    http://127.0.0.1:8080 — the WebUI user/pass. Note the
#                    port belongs to gluetun: qbittorrent runs inside
#                    protonvpn's netns (--network=container:protonvpn), so
#                    there is no qbittorrent-published port to point at.
#     pi_hole        http://127.0.0.1:8089, "Statistics only" off. This HA
#                    speaks the v6 API; pihole.nix sets no password, so the
#                    flow should take an empty one. Do NOT point it at
#                    /admin/ — webserver.paths.webhome is "/".
#     tailscale      needs an API key from
#                    https://login.tailscale.com/admin/settings/keys — this
#                    host had no Tailscale credential before, which is also
#                    why the tailnet DNS override in pihole.nix is documented
#                    as console-only state.
#
#   YAML REST SENSORS -- Prowlarr, Bazarr and Authentik have no core
#   integration at all, so they are the `sensor` list above. Their keys come
#   from /var/lib/hass/secrets.yaml, which hass-secrets.service regenerates on
#   every boot from the keys those services already keep on disk. Nothing to
#   do for Prowlarr and Bazarr. Authentik needs a token once -- see that
#   unit's comment. Rotating a Prowlarr or Bazarr key needs no rebuild, just
#   `systemctl restart hass-secrets home-assistant`.
#
#   NOT integrated, deliberately: nginx, gluetun/protonvpn, byparr and the
#   podman runtime itself. No core integrations exist, and a REST sensor would
#   have nothing meaningful to poll. If host-level visibility is wanted there,
#   systemmonitor plus the journal is a better answer than three more sensors.
#
# -- The recorder database ----------------------------------------------------
#   SQLite at /var/lib/hass/home-assistant_v2.db, pruned to 30 days by the
#   recorder.purge_keep_days above. Postgres is the usual upgrade and this box
#   already runs one for Authentik -- but that instance is a container on
#   authentik_default, so pointing HA at it would mean either publishing that
#   port or moving HA onto the bridge, and moving HA onto a bridge breaks the
#   multicast discovery this whole file is arranged around. Run a second
#   Postgres natively if it ever comes to that.
# =============================================================================
