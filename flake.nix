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
        devShell.x86_64-linux = pkgs.mkShell {
          buildInputs = [
            pkgs.python3
            pkgs.python3Packages.numpy
            pkgs.python3Packages.tkinter
            pkgs.python3Packages.pip
          ];

          shellHook = ''
            # Set up ROS environment (e.g., ROS Noetic, adjust as needed)
            source /opt/ros/noetic/setup.bash || echo "ROS setup not found"
            # Add Python path for rospy and clover
            export PYTHONPATH=${pkgs.python3Packages.rospy}/${pkgs.python3.sitePackages}:${pkgs.python3Packages.clover}/${pkgs.python3.sitePackages}
            echo "ROS and Clover environment setup complete."
          '';
        };

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
