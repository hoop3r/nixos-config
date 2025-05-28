{
  description = "my flake and whatnot";

  inputs = {

    nixpkgs = {
      url = "nixpkgs/nixos-25.05";
    };

    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprland = {
      url = "github:hyprwm/Hyprland";
    };

  };

  outputs = { nixpkgs, home-manager, hyprland, ... }@inputs:
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

        homeConfigurations = {
          thinkpad = home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            extraSpecialArgs = { inherit inputs; };
            modules = [ 
              ./home.nix 
              ./modules/git.nix
              ./modules/programs.nix
              ./modules/utilities.nix
              ./modules/vscode.nix
              ./modules/hyprland.nix
            ];
          };
        };

        nixosConfigurations = {
          thinkpad = lib.nixosSystem {
            inherit system pkgs;
            modules = [ 
              ./configuration.nix
              ./modules/specialisations.nix

            ];
          };
        };

      };
}
