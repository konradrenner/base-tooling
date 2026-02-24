

{
  description = "base-tooling: Konrad's declarative workstation base (Linux + macOS)";

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
    # Import nixpkgs with the nix4vscode overlay and unfree enabled.
    mkPkgs = system: import nixpkgs {
      inherit system;
      overlays = [ nix4vscode.overlays.default ];
      config.allowUnfree = true;
    };
  in
  {
    # ------------------------------
    # Linux: home-manager standalone
    # ------------------------------
    # Usage:
    #   nix run github:nix-community/home-manager -- switch --flake .#konrad@linux
    homeConfigurations."konrad@linux" = home-manager.lib.homeManagerConfiguration {
      pkgs = mkPkgs "x86_64-linux";
      modules = [
        ./home/common.nix
        ./home/linux.nix
      ];
    };

    # ------------------------------
    # macOS (Apple Silicon): nix-darwin + home-manager
    # ------------------------------
    # Usage:
    #   nix run github:nix-darwin/nix-darwin -- switch --flake .#default
    darwinConfigurations.default = nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      pkgs = mkPkgs "aarch64-darwin";
      modules = [
        ./darwin/configuration.nix

        # Home Manager integrated into nix-darwin.
        home-manager.darwinModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.konrad = import ./home/darwin.nix;
        }
      ];
    };
  };
}