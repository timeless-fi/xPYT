# load environment variables from .env
source .env

# set env variables
export ADDRESSES_FILE=./deployments/mainnet.json
export RPC_URL=$RPC_URL_MAINNET

# load common utilities
. $(dirname $0)/common.sh

# deploy contracts
factory_address=$(deploy xPYTFactory $UNIV3_FACTORY_MAINNET $UNIV3_QUOTER_MAINNET)
echo "xPYTFactory=$factory_address"