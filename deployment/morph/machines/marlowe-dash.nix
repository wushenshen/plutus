{ pkgs, config, lib, tfinfo, ... }:
{
  imports = [
    ./std.nix
    ../../../nix/modules/pab.nix
  ];

  networking = {
    firewall.allowedTCPPorts = [ 22 80 9080 ];
  };

  services.pab = {
    enable = true;
    pab-package = pkgs.plutus-pab.pab-exes.plutus-pab;
    contracts = [
      "${pkgs.marlowe-app}/bin/marlowe-app"
      "${pkgs.marlowe-companion-app}/bin/marlowe-companion-app"
      "${pkgs.marlowe-follow-app}/bin/marlowe-follow-app"
    ];
    staticContent = pkgs.marlowe-dashboard.client;
    dbFile = "/var/lib/pab/pab-core.db";
    defaultWallet = 1;
    webserverPort = 9080;
    walletPort = 8081;
    nodePort = 8082;
    chainIndexPort = 8083;
    signingProcessPort = 8084;
    metadataPort = 8085;
    zeroSlotTime = 1591566291; # POSIX time of 2020-06-07T21:44:51Z (Sunday, June 7, 2020 21:44:51)
    slotLength = 1;
  };

}
