{ pkgs, ... }:

let

  dotnet_sdk = pkgs.dotnetCorePackages.dotnet_8.sdk;
  dotnet_runtime = pkgs.dotnetCorePackages.dotnet_8.runtime;
  dotnet_aspnetcore = pkgs.dotnetCorePackages.dotnet_8.aspnetcore;

  packageOverrides = pkgs.callPackage ../python-packages.nix {};
  python = pkgs.python3.override { 
    inherit packageOverrides; 
  };

  dotnet-full = with pkgs.dotnetCorePackages; combinePackages [
    dotnet_sdk
    dotnet_runtime
    dotnet_aspnetcore
  ];

  deps = ps: with ps; [
    (python.withPackages (p: [
       p.requests 
       p.picozero 
       p.typing-extensions 
       p.adafruit-circuitpython-typing 
       p.Adafruit-PureIO 
       p.adafruit-circuitpython-busdevice 
       p.adafruit-circuitpython-requests 
       p.adafruit-circuitpython-sht31d 
       p.Adafruit-Blinka 
       p.Adafruit-PlatformDetect 
       p.matplotlib
      ]))

    zlib
    openssl.dev
    pkg-config
    stdenv.cc
    cmake
    mono
    dotnet-ef
  ] ++ [ dotnet-full ];
in
{

 programs.vscode = {
  enable = true;
  
  package =
    (pkgs.vscode.overrideAttrs (prevAttrs: {
      nativeBuildInputs = prevAttrs.nativeBuildInputs ++ [ pkgs.makeWrapper ];
      postFixup =
        prevAttrs.postFixup
        + ''
          wrapProgram $out/bin/code \
            --set DOTNET_ROOT "${dotnet_sdk}/share/dotnet" \
            --prefix PATH : "${dotnet_sdk}/share/dotnet/tools"
        '';
    })).fhsWithPackages
      (ps: deps ps);
  };

}
