{ config, pkgs, lib, profile, ... }:

# Bauform "notebook": Gerät mit Touchpad und internem Display.
# Sagt nichts über eine bestimmte Maschine oder ihren Hostnamen aus.

let
  # ── NetworkManager: DNS-Suchdomain fuer das interne WireGuard-VPN ──
  # Nur das Notebook nutzt das VPN, deshalb steht das hier im Profil
  # und nicht in home/linux.nix (das beide Profile teilen).
  #
  # nmConnection ist die WireGuard-Verbindung im NetworkManager. Die
  # Suchdomain wird nur auf DIESE Verbindung gesetzt, und nur wenn es
  # sie gibt — auf einem neuen Notebook ohne kuk-gateway passiert
  # einfach nichts, der Lauf bricht nicht ab.
  nmConnection = "kuk-gateway";
  nmSearchDomains = [ "famre.at" ];
in
{
  imports = [ ../../plasma/notebook.nix ];

  # Platz für Pakete, die nur auf mobilen Geräten Sinn haben.
  # home.packages = with pkgs; [ ];

  # ── NetworkManager: Suchdomain auf der VPN-Verbindung ─────────────
  # Das KDE-Netzwerk-Applet schreibt die Suchdomain in das
  # Verbindungsprofil unter /etc/NetworkManager/system-connections/
  # (dns-search= in den Abschnitten [ipv4] und [ipv6]). Dieses Profil
  # enthaelt bei WireGuard auch den Private Key und gehoert deshalb
  # NICHT ins Repo. Verwaltet wird nur diese eine Eigenschaft per nmcli
  # — derselbe Aufruf, den das Applet nutzt; polkit erlaubt ihn aus
  # einer aktiven Sitzung ohne sudo.
  #
  # Home Manager kann /etc nicht beschreiben (kein NixOS), deshalb ein
  # Aktivierungsschritt statt einer deklarativen Datei — dasselbe Muster
  # wie die Akonadi-Regel in home/linux.nix. Idempotent: bei gleichem
  # Stand laeuft nichts. Existiert die Verbindung nicht (z.B. neues
  # Notebook), wird nur eine Meldung ausgegeben — der Aktivierungslauf
  # bricht nicht ab. Eine bereits aktive VPN-Verbindung uebernimmt die
  # Aenderung beim naechsten Verbindungsaufbau (nmcli con down/up).
  home.activation.networkManagerDnsSearch =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      _conn="${nmConnection}"
      _want="${lib.concatStringsSep ";" nmSearchDomains}"

      if ! command -v nmcli >/dev/null 2>&1; then
        echo "nmcli nicht im PATH — Suchdomain wird nicht gesetzt."
      elif ! nmcli -t -f NAME con show "$_conn" >/dev/null 2>&1; then
        echo "NM-Verbindung $_conn nicht gefunden — nichts gesetzt."
        echo "Bekannte Verbindungen: nmcli -f NAME,TYPE con show"
      else
        _norm() { tr ', ' ';;' | tr -s ';' | sed 's/^;*//;s/;*$//'; }
        _have4="$(nmcli -g ipv4.dns-search con show "$_conn" 2>/dev/null | _norm || true)"
        _have6="$(nmcli -g ipv6.dns-search con show "$_conn" 2>/dev/null | _norm || true)"
        if [ "$_have4" = "$_want" ] && [ "$_have6" = "$_want" ]; then
          : # steht schon richtig, nichts tun
        elif nmcli con modify "$_conn" \
               ipv4.dns-search "$_want" \
               ipv6.dns-search "$_want"; then
          echo "Suchdomain auf $_conn gesetzt: $_want (ipv4 und ipv6)."
        else
          echo "WARNUNG: nmcli con modify $_conn ist fehlgeschlagen (polkit?)."
          echo "Manuell nachholen: nmcli con modify $_conn ipv4.dns-search \"$_want\" ipv6.dns-search \"$_want\""
        fi
      fi
    '';
}
