

{
  description = "base-tooling: Declarative base-tooling (Linux + macOS)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-darwin.url = "github:nix-darwin/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    # Used to install VS Code Marketplace extensions declaratively.
    nix4vscode.url = "github:nix-community/nix4vscode";
    nix4vscode.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, nixpkgs, home-manager, nix-darwin, nix4vscode, ... }:
  let
    username =
      let u = builtins.getEnv "BASE_TOOLING_USER";
      in if u != "" then u else throw "BASE_TOOLING_USER is not set (run install.sh/update.sh with --user ...)";

    mkPkgs = system: import nixpkgs {
      inherit system;
      overlays = [ nix4vscode.overlays.default ];
      config.allowUnfree = true;
    };
  in
  {
    homeConfigurations."${username}@linux" = home-manager.lib.homeManagerConfiguration {
      pkgs = mkPkgs "x86_64-linux";
      extraSpecialArgs = { inherit username; };
      modules = [
        ./home/common.nix
        ./home/linux.nix
      ];
    };

    darwinConfigurations.default = nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      pkgs = mkPkgs "aarch64-darwin";
      specialArgs = { inherit username; };
      modules = [
        ./darwin/configuration.nix

        home-manager.darwinModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = { inherit username; };

          home-manager.users.${username} = {
            imports = [
              ./home/common.nix
              ./home/darwin.nix
            ];
          };
        }
      ];
    };
  };
}
