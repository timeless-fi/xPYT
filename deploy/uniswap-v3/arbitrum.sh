# load environment variables from .env
source .env

# set env variables
export ADDRESSES_FILE=./deployments/arbitrum.json
export RPC_URL=$RPC_URL_ARBITRUM

# load common utilities
. $(dirname $0)/../common.sh

# deploy contracts
factory_address=$(deploy UniswapV3xPYTFactory $UNIV3_FACTORY $UNIV3_QUOTER)
echo "UniswapV3xPYTFactory=$factory_address"