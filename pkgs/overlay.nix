# Packages that nixpkgs either lacks or mis-builds on aarch64-darwin.
final: prev:

let
  inherit (final) lib stdenv;
  isAarch64Darwin = stdenv.hostPlatform.system == "aarch64-darwin";
in
{
  liberica-jdk-full = final.callPackage ./liberica-jdk-full/package.nix { };

  sleuthkit =
    (prev.sleuthkit.override {
      # nixpkgs builds the Java bindings with JDK 21, emitting class file version
      # 65. Autopsy runs on a JDK 17 (JavaFX), which rejects anything above 61.
      jdk = final.jdk17;
    }).overrideAttrs
      (old: {
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
          final.zip
          final.unzip
        ];

        # SleuthkitJNI loads its native library out of the jar, picking the
        # NATIVELIBS slot by `os.arch`, and gives up if the slot is missing —
        # it never falls back to java.library.path. The ant build files the
        # freshly built arm64 library under amd64/x86_64 only, so on Apple
        # Silicon the loader finds nothing. Copy it into the slot it looks in.
        postInstall = (old.postInstall or "") + lib.optionalString isAarch64Darwin ''
          for jar in "$out"/share/java/sleuthkit-*.jar; do
            case "$jar" in *caseuco*) continue ;; esac

            work=$(mktemp -d)
            ( cd "$work" && unzip -q "$jar" 'NATIVELIBS/*' )

            src="$work/NATIVELIBS/amd64/mac/libtsk_jni.jnilib"
            if [ ! -f "$src" ]; then
              echo "sleuthkit: no mac JNI in $jar; NATIVELIBS layout changed upstream" >&2
              exit 1
            fi

            mkdir -p "$work/NATIVELIBS/aarch64/mac"
            cp "$src" "$work/NATIVELIBS/aarch64/mac/libtsk_jni.jnilib"

            chmod +w "$jar"
            ( cd "$work" && zip -qr "$jar" NATIVELIBS/aarch64 )
            rm -rf "$work"
          done
        '';
      });

  # Shadows nixpkgs' x86_64-only `autopsy`.
  autopsy = final.callPackage ./autopsy/package.nix { };
}
