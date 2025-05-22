{ pkgs ? import <nixpkgs> { system = builtins.currentSystem; }
, appimageTools ? pkgs.appimageTools
, lib ? pkgs.lib
, fetchurl ? pkgs.fetchurl
}:

appimageTools.wrapType2 rec {
  pname = "cider";
  version = "2.6.1";

  src = fetchurl {
    url = "file://cider-linux-x64.AppImage";
    sha256 = "6ee1ee9d4b45419d7860d1e7831dc7c2a9b94689f013a0bf483876c6b4d65062";
  };

  extraInstallCommands =
    let contents = appimageTools.extract { inherit pname version src; };
    in ''
      install -m 444 -D ${contents}/*.desktop -t $out/share/applications
      substituteInPlace $out/share/applications/*.desktop \
        --replace 'Exec=AppRun' 'Exec=${pname}'
      cp -r ${contents}/usr/share/icons $out/share
    '';

  extraWrapperArgs = [
    "--set ELECTRON_DISABLE_SANDBOX 1"
    "--set CIDER_DISABLE_SANDBOX 1"
    "--add-flags --no-sandbox"
    "--add-flags --disable-gpu"
    "--add-flags --disable-software-rasterizer"
    "--add-flags --disable-gpu-compositing"
    "--add-flags --use-gl=swiftshader"
    "--add-flags --ozone-platform=x11"
    "--add-flags --ozone-platform=wayland"
  ];

  meta = with lib; {
    description = "A new look into listening and enjoying Apple Music in style and performance.";
    homepage = "https://cider.sh/";
    platforms = [ "x86_64-linux" ];
  };
}
