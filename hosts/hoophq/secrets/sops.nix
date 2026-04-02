{ config, pkgs, lib, ... }:

let
  user  = "bugbyte";
  hqDir = "/home/${user}/hq-nix-config";

  mkSecret = { file, key, path }: {
    sopsFile = file;
    inherit key path;
    format = "yaml";
    owner  = "feedbot";
    group  = "feedbot";
    mode   = "0640";
  };

in
{
  sops.age.keyFile = "./agekey.txt";

  sops.secrets = {
    strava_client_id = mkSecret {
      file = ./secrets/strava.yaml;
      key  = "CLIENT_ID";
      path = "/run/secrets/strava_client_id";
    };
    strava_client_secret = mkSecret {
      file = ./secrets/strava.yaml;
      key  = "CLIENT_SECRET";
      path = "/run/secrets/strava_client_secret";
    };
    strava_refresh_token = mkSecret {
      file = ./secrets/strava.yaml;
      key  = "REFRESH_TOKEN";
      path = "/run/secrets/strava_refresh_token";
    };
    lastfm_user = mkSecret {
      file = ./secrets/lastfm.yaml;
      key  = "USER";
      path = "/run/secrets/lastfm_user";
    };
    lastfm_apikey = mkSecret {
      file = ./secrets/lastfm.yaml;
      key  = "APIKEY";
      path = "/run/secrets/lastfm_apikey";
    };
    lastfm_endpoint = mkSecret {
      file = ./secrets/lastfm.yaml;
      key  = "ENDPOINT";
      path = "/run/secrets/lastfm_endpoint";
    };
  };
}