{ pkgs }:
# in the future this could just be a nix attr set turned into a json file
{ name
, db-file ? "/tmp/pab-core.db"
, client
, webserver-port ? "9080"
, walletserver-port ? "9081"
, nodeserver-port ? "9082"
, chain-index-port ? "9083"
, signing-process-port ? "9084"
, metadata-server-port ? "9085"
, wallet ? "1"
}: pkgs.writeText "pab.yaml" ''
  dbConfig:
      dbConfigFile: ${ db-file }
      dbConfigPoolSize: 20

  pabWebserverConfig:
    baseUrl: http://localhost:${ webserver-port }
    staticDir: ${ client }

  walletServerConfig:
    baseUrl: http://localhost:${ walletserver-port }
    wallet:
      getWallet: ${ wallet }

  nodeServerConfig:
    mscBaseUrl: http://localhost:${ nodeserver-port }
    mscSocketPath: /tmp/node-server.sock
    mscSlotLength: 5
    mscRandomTxInterval: 20000000
    mscSlotConfig:
      scZeroSlotTime: 1596059091 # POSIX time of 2020-07-29T21:44:51Z (Wednesday, July 29, 2020 21:44:51) - Shelley launch time
      scSlotLength: 1
    mscKeptBlocks: 100000
    mscInitialTxWallets:
      - getWallet: 1
      - getWallet: 2
      - getWallet: 3

  chainIndexConfig:
    ciBaseUrl: http://localhost:${ chain-index-port }
    ciWatchedAddresses: []

  requestProcessingConfig:
    requestProcessingInterval: 1

  signingProcessConfig:
    spBaseUrl: http://localhost:${ signing-process-port }
    spWallet:
      getWallet: ${ wallet }

  metadataServerConfig:
    mdBaseUrl: http://localhost:${ metadata-server-port }

''
