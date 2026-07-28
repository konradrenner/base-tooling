{ lib
, fetchurl
, appimageTools
, jdk
}:

# Ancestris gibt es weder auf Flathub noch in nixpkgs — nur als AppImage
# oder ZIP. Statt es im Bootstrap-Skript irgendwo herunterzuladen, wird es
# hier als reguläre Derivation mit gepinnter URL und Hash gebaut. Damit ist
# es genauso reproduzierbar wie alles andere aus Nix.
#
# ── EINMALIG AUSFÜLLEN ───────────────────────────────────────────────
# 1. Aktuelle AppImage-URL von https://www.ancestris.org holen und unten
#    bei `version` und `url` eintragen.
# 2. Hash ermitteln:
#       nix-prefetch-url --type sha256 "<url>"
#    oder einfach bauen — mit dem fakeHash unten bricht der Build ab und
#    nennt dir den echten Hash:
#       nix build .#ancestris
# 3. Hash bei `hash` eintragen.
#
# Bis dahin schlägt der Build dieses Pakets bewusst fehl, statt still
# etwas Falsches zu installieren.

let
  version = "14";

  src = fetchurl {
    url = "https://www.ancestris.org/dl/ancestris-${version}-latest.AppImage";
    hash = lib.fakeHash;
  };
in
appimageTools.wrapType2 {
  pname = "ancestris";
  inherit version src;

  # Ancestris ist eine Java-Anwendung. Falls das AppImage keine JRE
  # mitbringt, findet es hier eine.
  extraPkgs = pkgs: [ jdk ];

  meta = with lib; {
    description = "Ancestris — freie Genealogie-Software (GEDCOM)";
    homepage = "https://www.ancestris.org";
    license = licenses.gpl2Plus;
    platforms = [ "x86_64-linux" ];
    mainProgram = "ancestris";
  };
}
