# B2E2 - Smart Contracts

Based on experience with prototypical use cases, our team at [Energie Baden-Württemberg AG (EnBW)](https://www.enbw.com/) has written the whitepaper 'EnergyTokenModel'. In this paper we describe how distributed ledger technology or blockchain can be used in the energy industry providing a basis for a blockchain based energy ecosystem in which usecases as i.e. energy sharing, proof of origin, local markets can be realized. The presented approach shows a way how real-world objects can be digitally mapped on a blockchain and how properties and transactions can be documented in a trustworthy way. The White Paper is currently available for download in German language [here](https://it-architecture.enbw.com/whitepaper-energy-token-model/).
 
With the publication of the smart contracts in this repository we are taking the next step. After we have explained in the white paper how DLT mechanisms can be applied in the energy industry, we show here how the implementation looks like. Since we believe that the advantage of using DLT is to have a common transaction layer, we publish the repository under a MIT open source license. 

With our publications, we are contributing to the public discussion on how the block chain can be used in the energy industry and hope to receive further ideas and impulses.

The Blockchain identities are implemented with the [ERC725](https://github.com/ethereum/EIPs/issues/725) and [ERC735](https://github.com/ethereum/EIPs/issues/735) standards. The energy tokens are implemented with the [ERC1155](https://github.com/ethereum/EIPs/issues/1155) standard.

The latest version of the sequence and entity relationship diagrams from the whitepaper can be found in the directory './documentation'.  

## Cloning the repository
    git clone --recursive https://github.com/B2E2/b2e2_contracts.git

## Installing Dependencies
    sudo npm install -g truffle ganache ganache-cli
    cd Energietokens-Implementierung
    npm install
	cd dependencies/jsmnSol
	npm install

## Building & Deployment
Launch Ganache:

    npx ganache-cli -l 1000000000

Choose a sender address from the list that's printed and replace the address in the line containing `from:` in `truffle-config.js` by it.

Then (in a different terminal instance) compile the contracts and deploy them:

    npx truffle compile
    npx truffle deploy

## Testing

### Alternative 1

Launch Ganache:

    npx ganache-cli -l 1000000000 -m "bread leave edge glide soda seat trim armed canyon rural cross scheme"

Copy sender address 0 from the list that's printed and replace the address in the line containing `from:` in `truffle-config.js` by it.

Copy private key 9 and change the definition of `account9Sk` at the top of `test/IdentityContract.test.js` to it.

Run the tests (in a different terminal instance):

    npx truffle deploy # required for tests to run successfully
    npx truffle test

### Alternative 2

```
    npm run build
    npm run tests
```
