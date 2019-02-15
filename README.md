# Diamond network CDC token Smart Contract

One of the main purposes of [Diamond Network Project](https://cdiamondcoin.com/) is to create a diamond backed stable coin. To use the services of the platform you will need a utility token called [DPT](https://github.com/Cdiamondcoin/dpt-token) - Diamond Platform Token. Current repository contains the [ERC20](https://github.com/ethereum/EIPs/issues/20) compatible smart contract of CDC token, and also the smart contract supporting the Exchange of CDC.

## Prerequisities

In order to compile smart contracts you need to install [Dapphub](https://dapphub.com/)'s utilities. Namely: [dapp](https://dapp.tools/dapp/), [seth](https://dapp.tools/seth/), [solc](https://github.com/ethereum/solidity), [hevm](https://dapp.tools/hevm/), and [ethsign](https://github.com/dapphub/dapptools/tree/master/src/ethsign).

| Command | Description |
| --- | --- |
|`bash <(curl https://nixos.org/nix/install)` | install `nix` package manager.|
|`. "$HOME/.nix-profile/etc/profile.d/nix.sh"`| load config for `nix`|
|`git clone --recursive https://github.com/dapphub/dapptools $HOME/.dapp/dapptools` | download `dapp seth solc hevm ethsign` utilities|
|`nix-env -f $HOME/.dapp/dapptools -iA dapp seth solc hevm ethsign` | install `dapp seth solc hevm ethsign`. This will install utilities for current user only!!|

## Use custom version of solidity compiler

`dapp --use solc:0.4.24 build`

## Building smart contracts

The `build` command invokes `solc` to compile all code in `src` and `lib` to `out`.

`dapp build`

## Installing smart contracts

As a result of installation .abi and .bin files will be created in `cdc-token/out/` folder. These files can be installed later on mainnet.

| Command | Description |
| --- | --- |
|`git clone https://github.com/Cdiamondcoin/cdc-token.git` | Clone the smart contract code.|
|`cd cdc-token && git submodule update --init --recursive` | Update libraries to the latest version.|
|`dapp test` | Compile and test the smart contracts.|

## Deploying smart contracts

In order to deploy smart contracts you need to do the followings.
- Deploy `cdc-token/out/CDC.abi` `cdc-token/out/CDC.bin` to install cdc token.
- Deploy `cdc-token/out/CDCEXCHANGE.abi` `cdc-token/out/CDCEXCHANGE.bin` to install CDC EXCHANGE smart contract.
- Lets assume `CDC` is the address of CDC token, and `EXCHANGE` is the address of EXCHANGE smart contract. Execute as owner `(CDC).approve(EXCHANGE, uint(-1))` to enable for EXCHANGE smart contract to manipulate CDC tokens.

## Authors

- [Robert Horvath](https://github.com/r001)
- [Vitālijs Gaičuks](https://github.com/vgaicuks)
- [Aleksejs Osovitnijs](https://github.com/alexxxxey)

## License

This project is licensed under the GPL v3 License - see the [LICENSE](LICENSE) for details.
