{
  description = "My Home Manager configuration";

  inputs = {

    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs.url = "nixpkgs/nixos-24.11";

    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
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
      lib = nixpkgs.lib;
    in
      {
        homeConfigurations = {
          thinkpad = home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            extraSpecialArgs = { inherit inputs; };
            modules = [
            ];
          };
        };

        nixosConfigurations = {
          thinkpad = lib.nixosSystem {
            inherit system pkgs;
            modules = [ 
              ./modules
              ./hosts/thinkpad/configuration.nix
              ./hosts/thinkpad/hardware-configuration.nix

              {
                modules = {
                  git.enable = true;
                  hyprland.enable = true;
                  programs.enable = true;
                  utilities.enable = true;
                };
              }
              ./users
              ./users/hoop3r
            ];
          };
        };
      };
}
