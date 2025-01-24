{ pkgs, ... }:

let
  dotnet_sdk = pkgs.dotnetCorePackages.sdk_8_0_3xx;
  dotnet_runtime = pkgs.dotnetCorePackages.dotnet_8.runtime;
  dotnet_aspnetcore = pkgs.dotnetCorePackages.dotnet_8.aspnetcore;

  dotnet_full = with pkgs.dotnetCorePackages; combinePackages [
    dotnet_sdk
    dotnet_runtime
    dotnet_aspnetcore
  ];

  dotnet_deps = [
    mono
    msbuild
  ];

  dev_deps = [
    zlib
    openssl.dev
    pkg-config
    stdenv.cc
    cmake
  ];

  deps = ps: with ps; dev_deps ++ dotnet_deps ++ [ dotnet_full ];
in
{
  programs.vscode = {
    enable = true;
    package = pkgs.vscode.overrideAttrs (prevAttrs: {
      nativeBuildInputs = prevAttrs.nativeBuildInputs ++ [ pkgs.makeWrapper ];
      postFixup = prevAttrs.postFixup + ''
        wrapProgram $out/bin/code \
          --set DOTNET_ROOT "${dotnet_full}" \
          --prefix PATH : "~/.dotnet/tools"
      '';
    }).fhsWithPackages (ps: deps ps);
  };
}
