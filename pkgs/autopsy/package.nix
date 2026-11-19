{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
  sleuthkit,
  testdisk,
  imagemagick,
  liberica-jdk-full,
  gst_all_1,
  # Ingest is memory-hungry and the JVM otherwise takes a small default heap.
  # Solr runs as a separate process, so leave headroom below total RAM.
  maxHeapGb ? 8,
}:

# nixpkgs' own `autopsy` is `platforms = lib.platforms.x86_64` and packages the
# upstream zip, which has no aarch64-darwin story. This packages the community
# Apple Silicon bundle instead, but wires it to nixpkgs' Sleuth Kit rather than
# the /usr/local/lib symlinks its install script expects.
let
  gstLibPath = lib.makeLibraryPath [
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-libav
  ];

  runtimeBinPath = lib.makeBinPath [
    testdisk # PhotoRec Carver shells out to `photorec`
    imagemagick
    sleuthkit
  ];

  appDir = "${placeholder "out"}/Applications/Autopsy.app";
  resDir = "${appDir}/Contents/Resources/autopsy";
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "autopsy";
  version = "4.22.1b3";

  src = fetchurl {
    url = "https://github.com/markmckinnon/homebrew-sleuthkit/releases/download/Apple/autopsy-${finalAttrs.version}.zip";
    hash = "sha256-1se6CnRUBtzuMPdqdSrjaqC59fPsfBLhG/yWHbQ4AAY=";
  };

  nativeBuildInputs = [ unzip ];

  # The zip holds a single `autopsy.app`; stay in the build root so the copy below
  # controls the installed bundle name.
  sourceRoot = ".";

  # Preserve the vendor signatures on the bundled Mach-O helpers.
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/Applications" "$out/bin"
    cp -R autopsy.app "${appDir}"
    chmod -R u+w "${appDir}"

    # The zip loses the exec bits on the helper binaries and the Solr launcher.
    chmod -R a+x "${resDir}/autopsy/markmckinnon" "${resDir}/autopsy/solr/bin" "${resDir}/bin"

    # Take the Sleuth Kit Java bindings from the same build as the JNI dylib we
    # point java.library.path at below. The bundled jar and the dylib must come
    # from one Sleuth Kit or the native binding check fails when a case opens.
    rm -f "${resDir}/autopsy/modules/ext"/sleuthkit-*.jar
    cp ${sleuthkit}/share/java/sleuthkit-*.jar "${resDir}/autopsy/modules/ext/"

    # jdkhome and default_options are the only knobs the NetBeans launcher reads.
    # java.library.path is how the Sleuth Kit JNI is found, jna.library.path is
    # how the media player finds GStreamer.
    cat > "${resDir}/etc/autopsy.conf" <<'EOF'
    default_userdir="''${DEFAULT_USERDIR_ROOT}/dev"
    default_cachedir="''${DEFAULT_CACHEDIR_ROOT}/dev"
    jdkhome="${liberica-jdk-full}"
    default_options="--branding autopsy -J-Xmx${toString maxHeapGb}g -J-Djava.library.path=${sleuthkit}/lib -J-Djna.library.path=${gstLibPath}"
    EOF

    # The bundle seal no longer describes these contents. For an app whose entry
    # point is a shell script, a stale _CodeSignature is worse than none.
    rm -rf "${appDir}/Contents/_CodeSignature"

    # Launched from Finder there is no inherited PATH, and Solr cannot write
    # beside a read-only store path, so both are baked into the entry point.
    cat > "${appDir}/Contents/MacOS/autopsy" <<'EOF'
    #!/bin/sh
    export PATH="${runtimeBinPath}:$PATH"
    export SOLR_LOGS_DIR="$HOME/Library/Application Support/autopsy/dev/var/log"
    export SOLR_PID_DIR="$HOME/Library/Application Support/autopsy/dev"
    exec /bin/sh "${resDir}/bin/autopsy" "$@"
    EOF
    chmod +x "${appDir}/Contents/MacOS/autopsy"

    ln -s "${appDir}/Contents/MacOS/autopsy" "$out/bin/autopsy"

    runHook postInstall
  '';

  meta = {
    description = "Graphical interface to The Sleuth Kit and other open source digital forensics tools";
    homepage = "https://www.sleuthkit.org/autopsy";
    license = with lib.licenses; [
      asl20
      ipl10
      lgpl3Only
      lgpl21Only
      zlib
      bsd3
      mit
      gpl2Only
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "aarch64-darwin" ];
    mainProgram = "autopsy";
  };
})
