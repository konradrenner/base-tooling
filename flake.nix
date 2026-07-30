{
  description = "base-tooling: deklarative Linux-Workstation auf TuxedoOS (Home Manager + plasma-manager)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    nix-flatpak.url = "github:gmodena/nix-flatpak";
  };

  outputs = { self, nixpkgs, home-manager, plasma-manager, nix-flatpak, ... }:
    let
      system = "x86_64-linux";

      # Username und Home-Verzeichnis stehen bewusst NICHT im Repo.
      # Sie kommen aus der Umgebung des aufrufenden Users, deshalb braucht
      # `home-manager switch` ein --impure (siehe bootstrap.sh / sync.sh).
      #
      # Wichtig: Die Bindings sind lazy. `nix eval .#aptInstall` forciert sie
      # nicht und funktioniert daher ohne --impure.
      username =
        let u = builtins.getEnv "USER";
        in if u != "" then u
        else throw "USER ist nicht gesetzt. Nutze bootstrap.sh/sync.sh oder rufe nix mit --impure auf.";

      homeDirectory =
        let h = builtins.getEnv "HOME";
        in if h != "" then h
        else throw "HOME ist nicht gesetzt. Nutze bootstrap.sh/sync.sh oder rufe nix mit --impure auf.";

      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      sys = import ./system/packages.nix;
      repos = import ./system/repos.nix;

      # Profile beschreiben ausschliesslich die Hardware-Bauform, nicht eine
      # bestimmte Maschine: 'notebook' hat Touchpad und internes Display mit
      # eigener Skalierung, 'desktop' hat beides nicht. Mit dem Hostnamen hat
      # das nichts zu tun — bootstrap.sh/sync.sh erkennen die Bauform selbst
      # und verändern den Hostnamen nie.
      profiles = [ "notebook" "desktop" ];

      mkProfile = profile: home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = { inherit username homeDirectory profile; };
        modules = [
          plasma-manager.homeModules.plasma-manager
          nix-flatpak.homeManagerModules.nix-flatpak
          ./home/common.nix
          ./home/linux.nix
          ./home/profiles/${profile}.nix
        ];
      };

      space = builtins.concatStringsSep " ";
      lines = builtins.concatStringsSep "\n";
    in
    {
      homeConfigurations = builtins.listToAttrs
        (map (p: { name = p; value = mkProfile p; }) profiles);

      # ── Datenausgaben für die Shell-Skripte ───────────────────────────
      # Eine Quelle der Wahrheit: die Listen leben in system/packages.nix,
      # die Skripte lesen sie mit `nix eval --raw .#aptInstall`.
      aptInstall = space sys.apt.install;
      aptPurge = space sys.apt.purge;
      flatpakPackages = space sys.flatpak.packages;

      # Eine Zeile je .deb: name version sha256 url
      debList = lines (map (d: "${d.name} ${d.version} ${d.sha256} ${d.url}") sys.debs);

      profileList = space profiles;

      # Fremd-Repos als shell-auswertbare Blöcke (siehe system/repos.nix).
      aptRepoSetup = lines (map (r: r.setup) repos);
    };
}
