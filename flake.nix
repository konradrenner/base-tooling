{
  description = "base-tooling: declarative workstation base (Linux + macOS)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-darwin.url = "github:nix-darwin/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    # Declarative VS Code Marketplace extensions
    nix4vscode.url = "github:nix-community/nix4vscode";
    nix4vscode.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, nixpkgs, home-manager, nix-darwin, nix4vscode, ... }:
  let
    # Read the username from environment (requires --impure).
    username =
      let u = builtins.getEnv "BASE_TOOLING_USER";
      in if u != "" then u else throw ''
        BASE_TOOLING_USER is not set.

        Use install/update scripts with: --user <name>
        Or run nix with: BASE_TOOLING_USER=<name> ... --impure
      '';

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
    #   BASE_TOOLING_USER=... nix run github:nix-community/home-manager -- switch --impure --flake .#<user>@linux
    homeConfigurations."${username}@linux" = home-manager.lib.homeManagerConfiguration {
      pkgs = mkPkgs "x86_64-linux";
      extraSpecialArgs = { inherit username; };
      modules = [
        ./home/common.nix
        ./home/linux.nix
      ];
    };

    # ----------------------------------------
    # macOS (Apple Silicon): nix-darwin + HM
    # ----------------------------------------
    # Usage:
    #   BASE_TOOLING_USER=... nix build --impure .#darwinConfigurations.default.system
    #   sudo BASE_TOOLING_USER=... ./result/sw/bin/darwin-rebuild switch --impure --flake .#default
    darwinConfigurations.default = nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      pkgs = mkPkgs "aarch64-darwin";

      # Pass username to nix-darwin modules (e.g. darwin/configuration.nix)
      specialArgs = { inherit username; };

      modules = [
        ./darwin/configuration.nix

        home-manager.darwinModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;

          # Pass username into home-manager modules (e.g. home/common.nix)
          home-manager.extraSpecialArgs = { inherit username; };

          # IMPORTANT: bind HM user dynamically and import common + darwin
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
