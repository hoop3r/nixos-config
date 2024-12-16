{
  description = "My Home Manager configuration";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-24.11";
    
    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, ... }:
    let 
      system = "x86_64-linux";
      pkgs = import nixpkgs { 
        inherit system; 
        config = {
          allowUnfree = true;
        };
      };
      lib = nixpkgs.lib;
    in
      {
        homeConfigurations = {
          hoop3r = home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            modules = [ 
              ./home.nix 
              ./modules/hyprland.nix
              ./modules/git.nix
              ./modules/programs.nix
              ./modules/utilities.nix
            ];
          };
        };

        nixosConfigurations = {
          hoop3r = lib.nixosSystem {
            inherit system pkgs;
            modules = [ ./configuration.nix ];
          };
        };
      };
}
