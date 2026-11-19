{
  lib,
  stdenvNoCC,
  fetchurl,
}:

# BellSoft Liberica "full" JDK. Autopsy's media player, timeline and several
# option panels are JavaFX, and on aarch64-darwin there is no in-tree route to a
# JavaFX-capable JDK 17: nixpkgs' `jdk17` is Zulu CA (no JavaFX) and `openjfx17`
# is marked unsupported on this system. The "full" bundle ships JavaFX inline,
# and is the JDK the upstream macOS install notes assume.
let
  version = "17.0.20";
  build = "10";
in
stdenvNoCC.mkDerivation {
  pname = "liberica-jdk-full";
  inherit version;

  src = fetchurl {
    url = "https://github.com/bell-sw/Liberica/releases/download/${version}+${build}/bellsoft-jdk${version}+${build}-macos-aarch64-full.tar.gz";
    hash = "sha256-9klTX0LcvPiJ/QRN94L2oMtmlvhviOEMjsopztiIVyY=";
  };

  sourceRoot = "jdk-${version}-full.jdk";

  # Prebuilt, vendor-signed Mach-O. Any strip or install_name_tool pass
  # invalidates the signature, and arm64 refuses to exec unsigned code.
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -R . "$out"
    runHook postInstall
  '';

  meta = {
    description = "BellSoft Liberica JDK 17, full bundle (includes JavaFX)";
    homepage = "https://bell-sw.com/pages/downloads/";
    license = with lib.licenses; [
      gpl2Only
      classpathException20
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "aarch64-darwin" ];
    mainProgram = "java";
  };
}
