## How to create keystore file from private key

### Prerequisities

`pip install eth-account`

### Code

```python
import json
from eth_account import Account

enc = Account.encrypt('YOUR PRIVATE KEY', 'YOUR PASSWORD')

with open('/Users/vgaicuks/code/cdc-token/rinkeby.keystore', 'w') as f:
    f.write(json.dumps(enc))

```

## Verify contract code

### Flatten contract to upload code etherscan

```bash
hevm flatten --source-file src/Cdc.sol --json-file out/Cdc.sol.json > Cdc-flatt.sol
```

### Get compiller version (set on upload time)

```bash
solc --version
```

## Solc versioning

### Build app with selected compiler version

```bash
dapp --use solc:0.4.24 build
```

### Install another solc version

Just use non existing version in contract project path

```bash
dapp --use solc:0.4.25 test
```
