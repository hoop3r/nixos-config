{
  description = "My Home Manager configuration";

  inputs = {

    nixpkgs = {
      url = "nixpkgs/nixos-24.11";
    };

    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprland = {
      url = "github:hyprwm/Hyprland";
    };

  };

  outputs = { nixpkgs, home-manager, ... }@inputs:
    let 
      system = "x86_64-linux";
      pkgs = import nixpkgs { 
        inherit system; 
        config = {
          allowUnfree = true;
        };
      };

    packageOverrides = pkgs.callPackage ./python-packages.nix {};
    python = pkgs.python3.override { 
      inherit packageOverrides; 
    };

    lib = nixpkgs.lib;
      
    in
      {
        
        # devShells.x86_64-linux.default = pkgs.mkShell {
        #   buildInputs = [
        #     (python.withPackages (p: [ p.requests p.pygobject3 ]))
        #   ];

        #   shellHook = ''
        #     export GI_TYPELIB_PATH=${pkgs.gtk3}/lib/girepository-1.0:${pkgs.playerctl.override { introspection = true; }}/lib/girepository-1.0
        #   '';
        # };

        homeConfigurations = {
          thinkpad = home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            extraSpecialArgs = { inherit inputs; };
            modules = [ 
              ./home.nix 
              ./modules/hyprland.nix
              ./modules/git.nix
              ./modules/programs.nix
              ./modules/utilities.nix
              ./modules/vscode.nix
              ./modules/cider.nix
            ];
          };
        };

        nixosConfigurations = {
          thinkpad = lib.nixosSystem {
            inherit system pkgs;
            modules = [ 
              ./configuration.nix
            ];
          };
        };

      };
}
