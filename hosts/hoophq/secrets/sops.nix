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

}
