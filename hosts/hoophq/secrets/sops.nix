{ config, pkgs, lib, ... }: {

  sops.age.keyFile = "/home/bugbyte/.config/sops/age/keys.txt";

  sops.secrets.strava_client_id = {
    sopsFile = ./strava.yaml;
    key = "CLIENT_ID";
    group = config.services.nginx.group;
    mode = "0640";
    owner = config.services.nginx.user;
  };

  sops.secrets.strava_client_secret = {
    sopsFile = ./strava.yaml;
    key = "CLIENT_SECRET";
    group = config.services.nginx.group;
    mode = "0640";
    owner = config.services.nginx.user;
  };

  sops.secrets.strava_refresh_token = {
    sopsFile = ./strava.yaml;
    key = "REFRESH_TOKEN";
    group = config.services.nginx.group;
    mode = "0660";
    owner = config.services.nginx.user;
  };

  sops.secrets.lastfm_user = {
    sopsFile = ./lastfm.yaml;
    key = "USER";
    group = config.services.nginx.group;
    mode = "0640";
    owner = config.services.nginx.user;
  };

  sops.secrets.lastfm_apikey = {
    sopsFile = ./lastfm.yaml;
    key = "APIKEY";
    group = config.services.nginx.group;
    mode = "0640";
    owner = config.services.nginx.user;
  };

  sops.secrets.lastfm_endpoint = {
    sopsFile = ./lastfm.yaml;
    key = "ENDPOINT";
    group = config.services.nginx.group;
    mode = "0640";
    owner = config.services.nginx.user;
  };

  sops.secrets.authentik_pg_pass = {
    sopsFile = ./authentik.yaml;
    key      = "PG_PASS";
  };

  sops.secrets.authentik_secret_key = {
    sopsFile = ./authentik.yaml;
    key      = "SECRET_KEY";
  };

  sops.secrets.authentik_redis_pass = {
    sopsFile = ./authentik.yaml;
    key      = "REDIS_PASS";
  };

  sops.templates."authentik.env".content = ''
    POSTGRES_PASSWORD=${config.sops.placeholder.authentik_pg_pass}
    AUTHENTIK_POSTGRESQL__PASSWORD=${config.sops.placeholder.authentik_pg_pass}
    AUTHENTIK_SECRET_KEY=${config.sops.placeholder.authentik_secret_key}
    AUTHENTIK_REDIS__PASSWORD=${config.sops.placeholder.authentik_redis_pass}
    POSTGRES_USER=authentik
    POSTGRES_DB=authentik
  '';

  sops.templates."redis.conf" = {
    content = ''
      requirepass ${config.sops.placeholder.authentik_redis_pass}
      save 60 1
      loglevel warning
    '';
    mode = "0644";
  };


  # ---------------------------------------------------------------- wazuh ----
  #
  # Consumed by hosts/hoophq/wazuh.nix. Every one of these is handed to a
  # wazuh module as a *path* and read through a systemd LoadCredential, which
  # means PID 1 opens it as root before the service user is anywhere in the
  # picture. So the sops-nix default of root-owned 0400 is exactly right here
  # -- deliberately NOT the owner/group = nginx pattern used by the strava and
  # lastfm secrets above, which are read by a long-running worker process.
  #
  # The _PASS values are plaintext passwords; the _HASH values are the bcrypt
  # digests of the two indexer passwords. Both forms are stored because the
  # indexer wants hashes in internal_users.yml while the manager and dashboard
  # need the matching plaintext to authenticate, and Nix cannot bcrypt at
  # evaluation time. If you rotate a password you MUST regenerate its hash in
  # the same commit:
  #
  #   printf '%s' '<newpass>' | mkpasswd -m bcrypt -R 12 --stdin
  #
  # The _PASS values deliberately avoid space, '<', '$' and backslash: the
  # wazuh modules require single-line printable-ASCII secret files without
  # them. The _HASH values start with '$2b$' and that is expected -- the
  # no-'$' rule applies to passwords, not to the bcrypt digests.
  sops.secrets.wazuh_indexer_admin_pass = {
    sopsFile = ./wazuh.yaml;
    key      = "INDEXER_ADMIN_PASS";
  };

  sops.secrets.wazuh_indexer_admin_hash = {
    sopsFile = ./wazuh.yaml;
    key      = "INDEXER_ADMIN_HASH";
  };

  sops.secrets.wazuh_indexer_kibanaserver_pass = {
    sopsFile = ./wazuh.yaml;
    key      = "INDEXER_KIBANASERVER_PASS";
  };

  sops.secrets.wazuh_indexer_kibanaserver_hash = {
    sopsFile = ./wazuh.yaml;
    key      = "INDEXER_KIBANASERVER_HASH";
  };

  sops.secrets.wazuh_api_wazuh_pass = {
    sopsFile = ./wazuh.yaml;
    key      = "API_WAZUH_PASS";
  };

  sops.secrets.wazuh_api_wui_pass = {
    sopsFile = ./wazuh.yaml;
    key      = "API_WUI_PASS";
  };

  # Shared with mcpro: this same value must be in /etc/wazuh/authd.pass on the
  # Mac, which sops does not manage (no age key over there). See the enrollment
  # notes in hosts/mcpro/wazuh-agent.nix. Read it out with:
  #   sops -d hosts/hoophq/secrets/wazuh.yaml | grep AUTHD_PASS
  sops.secrets.wazuh_authd_pass = {
    sopsFile = ./wazuh.yaml;
    key      = "AUTHD_PASS";
  };
}
