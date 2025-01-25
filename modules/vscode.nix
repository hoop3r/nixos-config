{ pkgs, ... }:

let
  dotnet_sdk = pkgs.dotnetCorePackages.dotnet_8.sdk;
  dotnet_runtime = pkgs.dotnetCorePackages.dotnet_8.runtime;
  dotnet_aspnetcore = pkgs.dotnetCorePackages.dotnet_8.aspnetcore;

  dotnet-full = with pkgs.dotnetCorePackages; combinePackages [
    dotnet_sdk
    dotnet_runtime
    dotnet_aspnetcore
    sdk_6_0_1xx
  ];

  deps = ps: with ps; [
    zlib
    openssl.dev
    pkg-config
    stdenv.cc
    cmake
    mono
    # msbuild
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
  extensions = [
  ];
};

}
