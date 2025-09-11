#{ pkgs , inputs, ... }:

#let
#  pkgs = nixpkgs.legacyPackages.x86_64-linux;
#in
#  {
#  packages = {

    #appimageTools.wrapType2 rec {
    #  pname = "cidertest";
    #  version = "2.6.1";
    #  src = "./cider-linux-x64.AppImage";

    #  meta = with lib; {
    #    description = "A new look into listening and enjoying Apple Music in style and performance.";
    #    homepage = "https://cider.sh/";
    ##    platforms = [ "x86_64-linux" ];
    #  };
   # };
 # };
#}

