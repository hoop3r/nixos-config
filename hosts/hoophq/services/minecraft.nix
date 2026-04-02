{ config, pkgs, lib, ... }:

{
  services.minecraft-servers = {
    enable       = true;
    eula         = true;
    openFirewall = true;

   servers.vanilla = {
      enable     = true;
      package    = pkgs.papermcServers.papermc-1_21_10;

      whitelist = {
        SomeGuy07 = "394d1863-d2ac-4d12-ae81-dba8e34e3346";
        heheimshort = "f25f8d16-48a4-410f-a667-1d40856cbff7";
        AJKruer03 = "efdd3785-e366-453a-9722-b8fb38ce5093";
        Movabletoast203 = "e3484918-123c-4151-90dd-d60645bff26f";
        Sheen1233 = "3b88f8b3-aa53-4923-b732-e62a65845bc0";
        xXNighthawkXx = "459fd91c-86a2-41a7-b8b3-6253128f8c73";
        JGDIZZLE = "605b4193-e69d-4461-bffb-3d8453843a86";
        luroramo = "a172b276-e0cf-4787-a1da-e6f719206912";
        Squidkiller1000 = "8329a8a0-60ee-48e8-9182-8502a3c232f7";
        eef03 = "10533d15-8b85-4194-9f4f-552a8751b6ce";
        dominicladuke = "5e0de85f-b83b-4fd7-9e9f-557745822bd1";
        NONAME6912 = "4f2e5c8f-4f14-4931-84bf-9eb3206aaf8c";
        Squidkiller1001 = "03598849-9207-47fa-befe-f49e424ef535";
      #rip	OrinTheRuined = "f2048c0c-600e-4b7e-a28d-59ae1150e932";
        Dear_Pru = "b71fe9e4-e056-4b77-87d5-346b7aabd264";
        kcehlilpy = "cc825fca-4bc4-4c9e-9ea0-e2b27d7ea7da";
        camigirl09 = "9652ebdd-96e9-4b79-a5de-1f335325e467";
      };

      serverProperties = {
        motd         = "must use 1.21.10";
        max-players  = 20;
        difficulty   = "normal";
        gamemode     = "survival";
        online-mode  = true;
        pvp          = true;
        level-name   = "hoop_world";
        allow-flight = true;
        white-list   = true;
        server-port  = 25565;
      };
    };
  };
}