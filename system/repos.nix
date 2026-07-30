# Fremd-apt-Repos als Shell-Blöcke.
#
# Werden von bootstrap.sh über `nix eval --raw .#aptRepoSetup` gelesen und
# ausgeführt. Alle Blöcke sind idempotent: mehrfaches Ausführen ist gefahrlos.
#
# Wichtig zur Distro-Erkennung: TuxedoOS meldet in /etc/os-release
# möglicherweise ein eigenes ID (nicht "ubuntu"). Deshalb wird hier
# durchgehend "ubuntu" als Repo-Distribution hartkodiert und nur der
# Codename aus UBUNTU_CODENAME gelesen — das ist bei Ubuntu-Derivaten
# der verlässliche Weg.

[
  {
    name = "docker";
    setup = ''
      # Docker CE — Winboat unterstützt weder Podman noch rootless.
      if [ ! -f /etc/apt/keyrings/docker.asc ]; then
        sudo install -m 0755 -d /etc/apt/keyrings
        sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
          -o /etc/apt/keyrings/docker.asc
        sudo chmod a+r /etc/apt/keyrings/docker.asc
      fi
      CODENAME="$(. /etc/os-release && echo "''${UBUNTU_CODENAME:-$VERSION_CODENAME}")"
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $CODENAME stable" \
        | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    '';
  }

  {
    name = "vscode";
    setup = ''
      # VS Code aus dem Microsoft-Repo
      if [ ! -f /etc/apt/keyrings/microsoft.gpg ]; then
        sudo install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
          | gpg --dearmor \
          | sudo tee /etc/apt/keyrings/microsoft.gpg > /dev/null
        sudo chmod a+r /etc/apt/keyrings/microsoft.gpg
      fi
      echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
        | sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null
    '';
  }

  {
    name = "spotify";
    setup = ''
      # Spotify als natives .deb statt als Flatpak.
      #
      # Grund: Spotifys Flatpak ist ein extra-data-Paket und fuehrt bei der
      # Installation apply_extra in bwrap mit eigenem Netzwerk-Namespace aus.
      # Ubuntu 24.04+ setzt kernel.apparmor_restrict_unprivileged_userns=1 und
      # verbietet damit das Aufsetzen des Loopback-Interface:
      #   bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted
      # Der apt-Weg loest das Problem, statt eine systemweite Absicherung fuer
      # eine einzelne App zu lockern.
      #
      # Abweichend von Spotifys eigener Anleitung landet der Schluessel NICHT
      # in /etc/apt/trusted.gpg.d — dort waere er fuer jedes Repo gueltig.
      # Mit signed-by gilt er nur fuer dieses eine.
      #
      # Spotify rotiert den Schluessel gelegentlich. Aktuelle URL steht auf
      # https://www.spotify.com/de/download/linux/
      if [ ! -f /etc/apt/keyrings/spotify.gpg ]; then
        sudo install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.spotify.com/debian/pubkey_5384CE82BA52C83A.asc \
          | gpg --dearmor \
          | sudo tee /etc/apt/keyrings/spotify.gpg > /dev/null
        sudo chmod a+r /etc/apt/keyrings/spotify.gpg
      fi
      echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/spotify.gpg] https://repository.spotify.com stable non-free" \
        | sudo tee /etc/apt/sources.list.d/spotify.list > /dev/null
    '';
  }

  {
    name = "google-chrome";
    setup = ''
      # Google Chrome
      if [ ! -f /etc/apt/keyrings/google-chrome.gpg ]; then
        sudo install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
          | gpg --dearmor \
          | sudo tee /etc/apt/keyrings/google-chrome.gpg > /dev/null
        sudo chmod a+r /etc/apt/keyrings/google-chrome.gpg
      fi
      echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" \
        | sudo tee /etc/apt/sources.list.d/google-chrome.list > /dev/null
    '';
  }
]
