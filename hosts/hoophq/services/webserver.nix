{ config, pkgs, lib, ... }:

let
  user = "bugbyte";
  hqDir = "/home/${user}/hq-nix-config";

  pythonEnv = pkgs.python313.withPackages (p: [
    p.requests p.feedparser p.pyyaml p.fastapi
  ]);

  letterboxd2json = pkgs.writeScriptBin "letterboxd2json" ''
    #!${pythonEnv}/bin/python

    import feedparser, json, pathlib, requests, re, sys, html
    from email.utils import parsedate_to_datetime as p2d

    FEED = "https://letterboxd.com/hoop3r/rss/"
    OUT  = pathlib.Path("/var/www/www-hoopr3/feeds/lbx.json")
    OUT.parent.mkdir(parents=True, exist_ok=True)

    def extract(desc: str):
        m       = re.search(r'<img[^>]+src="([^"]+)"', desc)
        poster  = m.group(1) if m else None
        review_html = re.sub(r"<img[^>]+>", "", desc, count=1)
        review      = re.sub(r"</?[^>]+>", "", review_html).strip()
        return poster, html.unescape(review)

    def main():
        r = requests.get(FEED,
                         headers={"User-Agent": "hoop3r-feedbot/1.0"},
                         timeout=10)
        r.raise_for_status()
        feed = feedparser.parse(r.text)

        items = []
        for e in feed.entries[:20]:
            poster, review = extract(e.description)
            items.append({
                "title":     e.get("letterboxd_filmtitle", e.title),
                "year":      e.get("letterboxd_filmyear"),
                "link":      e.link,
                "poster":    poster,
                "rating":    float(e.get("letterboxd_memberrating", 0) or 0),
                "rewatch":   e.get("letterboxd_rewatch") == "Yes",
                "watched":   e.get("letterboxd_watcheddate"),
                "published": p2d(e.published).isoformat(),
                "review":    review,
            })

        OUT.write_text(json.dumps({"items": items}, separators=(",",":")))

    if __name__ == "__main__":
        sys.exit(main())
  '';

  stravaGrabber = pkgs.writeScriptBin "stravaGrabber" ''
    #!${pythonEnv}/bin/python

    import os, json, requests, sys
    from pathlib import Path
    from datetime import datetime

    CLIENT_ID_FILE     = Path("/run/secrets/strava_client_id")
    CLIENT_SECRET_FILE = Path("/run/secrets/strava_client_secret")
    REFRESH_TOKEN_FILE = Path("/run/secrets/strava_refresh_token")

    try:
        CLIENT_ID     = CLIENT_ID_FILE.read_text().strip()
        CLIENT_SECRET = CLIENT_SECRET_FILE.read_text().strip()
        REFRESH_TOKEN = REFRESH_TOKEN_FILE.read_text().strip()
    except FileNotFoundError as e:
        print(f"Secret file not found: {e}", file=sys.stderr)
        sys.exit(1)

    OUT = Path("/var/www/www-hoopr3/feeds/strava.json")
    OUT.parent.mkdir(parents=True, exist_ok=True)

    def refresh_access_token():
        global REFRESH_TOKEN
        resp = requests.post(
            "https://www.strava.com/oauth/token",
            data={
                "client_id":     CLIENT_ID,
                "client_secret": CLIENT_SECRET,
                "grant_type":    "refresh_token",
                "refresh_token": REFRESH_TOKEN,
            },
            timeout=10,
        )
        resp.raise_for_status()
        data = resp.json()
        new_refresh_token = data["refresh_token"]
        REFRESH_TOKEN_FILE.write_text(new_refresh_token)
        REFRESH_TOKEN = new_refresh_token
        return data["access_token"]

    def fetch_recent_activities():
        token = refresh_access_token()
        resp = requests.get(
            "https://www.strava.com/api/v3/athlete/activities",
            headers={"Authorization": f"Bearer {token}"},
            params={"per_page": 5},
            timeout=10,
        )
        resp.raise_for_status()
        return [
            {
                "id":                     a.get("id"),
                "name":                   a.get("name"),
                "type":                   a.get("type"),
                "distance_m":             a.get("distance"),
                "moving_time_s":          a.get("moving_time"),
                "elapsed_time_s":         a.get("elapsed_time"),
                "start_date":             a.get("start_date"),
                "average_speed_m_s":      a.get("average_speed"),
                "max_speed_m_s":          a.get("max_speed"),
                "total_elevation_gain_m": a.get("total_elevation_gain"),
                "calories":               a.get("calories"),
                "gear_id":                a.get("gear_id"),
                "commute":                a.get("commute"),
                "trainer":                a.get("trainer"),
            }
            for a in resp.json()
        ]

    def main():
        data = {
            "last_updated": datetime.utcnow().isoformat(),
            "activities":   fetch_recent_activities(),
        }
        OUT.write_text(json.dumps(data, separators=(",", ":")))
        print(f"Wrote {len(data['activities'])} recent activities to {OUT}")

    if __name__ == "__main__":
        main()
  '';

  lastfm = pkgs.writeScriptBin "lastfm" ''
    #!${pythonEnv}/bin/python

    import requests, json, sys
    from datetime import datetime

    SECRET_ENDPOINT_PATH = "/run/secrets/lastfm_endpoint"
    SECRET_API_KEY_PATH  = "/run/secrets/lastfm_apikey"
    SECRET_API_USER_PATH = "/run/secrets/lastfm_user"
    OUTPUT_FILE          = "/var/www/www-hoopr3/feeds/lastfm.json"

    def read_secret(path: str) -> str:
        try:
            value = open(path).read().strip()
            if not value:
                raise ValueError(f"Secret at {path} is empty")
            return value
        except Exception as e:
            raise RuntimeError(f"Failed to read secret {path}: {e}")

    ENDPOINT = read_secret(SECRET_ENDPOINT_PATH)
    API_KEY  = read_secret(SECRET_API_KEY_PATH)
    USERNAME = read_secret(SECRET_API_USER_PATH)

    def fetch_lastfm_data():
        try:
            url  = f"{ENDPOINT}&user={USERNAME}&api_key={API_KEY}&format=json"
            print(f"[{datetime.now().isoformat()}] Fetching Last.fm data")
            resp = requests.get(url, timeout=10)
            resp.raise_for_status()
            return resp.json()
        except Exception as e:
            raise RuntimeError(f"Failed to fetch Last.fm data: {e}")

    def main():
        import os
        data = fetch_lastfm_data()
        os.makedirs(os.path.dirname(OUTPUT_FILE), exist_ok=True)
        with open(OUTPUT_FILE, "w") as f:
            json.dump(data, f, separators=(",", ":"))
        print(f"[{datetime.now().isoformat()}] Wrote data to {OUTPUT_FILE}")

    if __name__ == "__main__":
        main()
  '';

  # Shared reverse proxy headers
  proxyHeaders = ''
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $http_connection;
    proxy_redirect off;
  '';

  proxyLocation = port: {
    proxyPass      = "http://127.0.0.1:${toString port}";
    proxyWebsockets = true;
    extraConfig    = proxyHeaders;
  };

  proxyVhost = port: {
    addSSL      = true;
    enableACME  = true;
    locations."/" = proxyLocation port;
  };

in
{
  users.users.feedbot = {
    isSystemUser = true;
    group        = "feedbot";
    home         = "/var/empty";
  };
  users.groups.feedbot = {};

  environment.systemPackages = [
    pkgs.ipset pkgs.curl pkgs.iptables
    letterboxd2json stravaGrabber lastfm
  ];

  systemd.services.lbx-feed = {
    description = "Fetch Letterboxd RSS and convert to JSON";
    script      = "${letterboxd2json}/bin/letterboxd2json";
    serviceConfig = {
      Type = "oneshot";
      User = "feedbot";
    };
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
  };

  systemd.timers.lbx-feed = {
    wantedBy    = [ "timers.target" ];
    timerConfig = {
      OnBootSec       = "5m";
      OnUnitActiveSec = "30m";
      Persistent      = true;
    };
  };

  systemd.services.strava-feed = {
    description = "Fetch Strava latest activity and convert to JSON";
    script      = "${stravaGrabber}/bin/stravaGrabber";
    serviceConfig = {
      Type = "oneshot";
      User = "feedbot";
    };
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
  };

  systemd.timers.strava-feed = {
    wantedBy    = [ "timers.target" ];
    timerConfig = {
      OnBootSec       = "5m";
      OnUnitActiveSec = "360m";
      Persistent      = true;
    };
  };

  systemd.services.lastfm-feed = {
    description = "Fetch Last.fm activity";
    script      = "${lastfm}/bin/lastfm";
    serviceConfig = {
      Type             = "oneshot";
      User             = "feedbot";
      Group            = "feedbot";
      WorkingDirectory = "/var/www/www-hoopr3/feeds";
      ReadWritePaths   = [ "/var/www/www-hoopr3/feeds" ];
      ProtectSystem    = "strict";
      ProtectHome      = "read-only";
      Restart          = "on-failure";
    };
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
  };

  systemd.timers.lastfm-feed = {
    wantedBy    = [ "timers.target" ];
    timerConfig = {
      OnBootSec       = "2m";
      OnUnitActiveSec = "15m";
      Persistent      = true;
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/www/www-hoopr3/feeds 0755 feedbot feedbot -"
    "f /var/www/www-hoopr3/feeds/lbx.json    0644 feedbot feedbot -"
    "f /run/secrets/strava_client_id         0640 root    feedbot -"
    "f /run/secrets/strava_client_secret     0640 root    feedbot -"
    "f /run/secrets/strava_refresh_token     0640 root    feedbot -"
    "f /run/secrets/lastfm_endpoint          0640 root    feedbot -"
    "f /run/secrets/lastfm_apikey            0640 root    feedbot -"
    "f /run/secrets/lastfm_user              0640 root    feedbot -"
  ];

  systemd.services.cloudflare-ips = {
    description = "Refresh Cloudflare IP ranges (ipset)";
    path        = [ pkgs.ipset pkgs.curl ];
    script = ''
      set -eu -o pipefail
      ipset -! create cf4 hash:net family inet  maxelem 65536
      ipset -! create cf6 hash:net family inet6 maxelem 65536
      ipset flush cf4
      ipset flush cf6
      curl -fsSL https://www.cloudflare.com/ips-v4 | xargs -I{} ipset add cf4 {}
      curl -fsSL https://www.cloudflare.com/ips-v6 | xargs -I{} ipset add cf6 {}

      mkdir -p /var/lib/cloudflare-realip
      {
        curl -fsSL https://www.cloudflare.com/ips-v4 | sed 's/^/set_real_ip_from /; s/$/ ;/'
        curl -fsSL https://www.cloudflare.com/ips-v6 | sed 's/^/set_real_ip_from /; s/$/ ;/'
        echo "real_ip_header CF-Connecting-IP;"
      } > /var/lib/cloudflare-realip/nginx.conf

      systemctl reload nginx
    '';
    serviceConfig.Type = "oneshot";
    before  = [ "nginx.service" ];
    after   = [ "network-online.target" ];
    wants   = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  systemd.timers.cloudflare-ips = {
    wantedBy    = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };

  networking.firewall = {
    allowedTCPPorts = [ 22 25565 80 443 ];
    extraCommands = ''
      iptables  -I INPUT -p tcp -m multiport --dports 80,443 \
                -m set ! --match-set cf4 src -j DROP
      ip6tables -I INPUT -p tcp -m multiport --dports 80,443 \
                -m set ! --match-set cf6 src -j DROP
    '';
  };

  services.fail2ban = {
    enable     = true;
    maxretry   = 5;
    ignoreIP   = [ "10.0.0.0/8" "192.168.0.0/16" ];
    jails = {
      sshd.settings = {
        enabled = true;
        backend = "systemd";
        mode    = "aggressive";
        filter  = "sshd";
      };
      nginx-bad-request.settings = {
        enabled  = true;
        backend  = "auto";
        filter   = "nginx-bad-request";
        logPath  = "/var/log/nginx/access.log";
        action   = "iptables-multiport[name=nginx-bad-request, port=\"http,https\"]";
        maxRetry = 3;
        findTime = "600";
        bantime  = "600";
      };
      nginx-botsearch.settings = {
        enabled  = true;
        backend  = "auto";
        filter   = "nginx-botsearch";
        logPath  = "/var/log/nginx/access.log";
        action   = "iptables-multiport[name=nginx-botsearch, port=\"http,https\"]";
        maxRetry = 3;
        findTime = "600";
        bantime  = "600";
      };
      nginx-error-common.settings = {
        enabled  = true;
        backend  = "auto";
        filter   = "nginx-error-common";
        logPath  = "/var/log/nginx/error.log";
        action   = "iptables-multiport[name=nginx-error-common, port=\"http,https\"]";
        maxRetry = 5;
        findTime = "600";
        bantime  = "600";
      };
      nginx-forbidden.settings = {
        enabled  = true;
        backend  = "auto";
        filter   = "nginx-forbidden";
        logPath  = "/var/log/nginx/access.log";
        action   = "iptables-multiport[name=nginx-forbidden, port=\"http,https\"]";
        maxRetry = 3;
        findTime = "600";
        bantime  = "600";
      };
      nginx-http-auth.settings = {
        enabled  = true;
        backend  = "auto";
        filter   = "nginx-http-auth";
        logPath  = "/var/log/nginx/error.log";
        action   = "iptables-multiport[name=nginx-http-auth, port=\"http,https\"]";
        maxRetry = 3;
        findTime = "600";
        bantime  = "600";
      };
      nginx-limit-req.settings = {
        enabled  = true;
        backend  = "auto";
        filter   = "nginx-limit-req";
        logPath  = "/var/log/nginx/access.log";
        action   = "iptables-multiport[name=nginx-limit-req, port=\"http,https\"]";
        maxRetry = 5;
        findTime = "600";
        bantime  = "600";
      };
    };
  };

  services.openssh = {
    enable                    = true;
    settings.PermitRootLogin  = "no";
    settings.PasswordAuthentication = false;
    authorizedKeysFiles       = [ "~/.ssh/authorized_keys" ];
  };

  services.nginx = {
    enable = true;
    appendHttpConfig = ''
      include /var/lib/cloudflare-realip/nginx.conf;

      map $scheme $hsts_header {
          https "max-age=31536000; includeSubdomains; preload";
      }

      add_header Strict-Transport-Security $hsts_header always;
      add_header Referrer-Policy           "origin-when-cross-origin" always;
      add_header X-Frame-Options           "DENY" always;
      add_header X-Content-Type-Options    "nosniff" always;
      add_header Content-Security-Policy   "default-src 'self'; script-src 'self'; object-src 'none';" always;
      proxy_cookie_path / "/; secure; HttpOnly; SameSite=strict";
    '';

    virtualHosts = {
      "hoop3r.com" = {
        addSSL     = true;
        enableACME = true;
        root       = "/var/www/www-hoopr3";
      };

      "howdyitsanna.com" = {
        addSSL     = true;
        enableACME = true;
        root       = "/var/www/www-howdyitsanna";
      };

      "mc.hoop3r.com" = {
        addSSL      = true;
        enableACME  = true;
        extraConfig = "return 444;";
      };

      "plex.hoop3r.com" = proxyVhost 32400;
      "r.hoop3r.com"    = proxyVhost 7878;
      "q.hoop3r.com"    = proxyVhost 8080;
      "s.hoop3r.com"    = proxyVhost 8989;
      "p.hoop3r.com"    = proxyVhost 9696;
      "b.hoop3r.com"    = proxyVhost 8191;
      "dns.hoop3r.com"  = proxyVhost 8053;
    };
  };

  security.acme = {
    acceptTerms     = true;
    defaults.email  = "nhoop2107@gmail.com";
  };
}