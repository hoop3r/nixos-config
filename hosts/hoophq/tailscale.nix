{ config, pkgs, lib, ... }:

let
  extIface = "wlp0s20f3";
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

  services.nginx.virtualHosts."hoop3r.com".locations."= /.well-known/webfinger" = {
    extraConfig = ''
      default_type application/jrd+json;
      return 200 '{"subject":"acct:nicholas@hoop3r.com","links":[{"rel":"http://openid.net/specs/connect/1.0/issuer","href":"https://auth.hoop3r.com/application/o/tailscale/"}]}';
    '';
  };
}
