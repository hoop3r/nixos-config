{
  description = "my flake and whatnot";

  inputs = {

    nixpkgs = {
      url = "nixpkgs/nixos-25.11";
    };

    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprland = {
      url = "github:hyprwm/Hyprland";
    };

    nix-minecraft = {
      url  = "github:Infinidoge/nix-minecraft";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
    };
    unstable = {
      url = "nixpkgs/nixos-unstable";
    }; 

    hoophq-services = {
      url = "git+ssh://git@github.com/hoop3r/hoophq-services.git";
#      rev = "4743b4b";
    };

  };

  outputs = { nixpkgs, home-manager, hyprland, nix-minecraft, sops-nix, unstable, hoophq-services, ... }@inputs:
    let 
      system = "x86_64-linux";

      unstablePkgs = import unstable {
        inherit system;
        config = {
          allowUnfree = true;
        };
      };

      pkgs = import nixpkgs { 
        inherit system; 
        config = {
          allowUnfree = true;
        };
        overlays = [
          nix-minecraft.overlays.default
          (self: super: {
            papermcServers = unstablePkgs.papermcServers;
          })
        ];
      };
	
      pkgslegacy = nixpkgs.legacyPackages.x86_64-linux;

      lib = nixpkgs.lib;
      
    in
      {

        homeConfigurations = {
          thinkpad = home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            extraSpecialArgs = { inherit inputs; };
            modules = [ 
              ./hosts/thinkpad/home.nix 
              ./hosts/thinkpad/modules/git.nix
              ./hosts/thinkpad/modules/hyprland.nix
              ./hosts/thinkpad/modules/programs.nix
              ./hosts/thinkpad/modules/utilities.nix
              ./hosts/thinkpad/modules/vscode.nix
            ];
          };
        };

        nixosConfigurations = {
          thinkpad = lib.nixosSystem {
            inherit system pkgs;
            specialArgs = { inherit inputs; };
            modules = [ 
              ./hosts/thinkpad/configuration.nix
              ./hosts/thinkpad/hardware-configuration.nix
              ./hosts/thinkpad/specialisations.nix
            ];
          };
          hoophq = lib.nixosSystem {
            inherit system pkgs;
            specialArgs = { inherit inputs; };
            modules = [ 
              ./hosts/hoophq/configuration.nix
              ./hosts/hoophq/hardware-configuration.nix
              hoophq-services.nixosModules.containers
              hoophq-services.nixosModules.minecraft
              hoophq-services.nixosModules.webserver
              ./hosts/hoophq/secrets/sops.nix
              sops-nix.nixosModules.sops
              nix-minecraft.nixosModules.minecraft-servers
            ];
          };
        };

      };
}
