# load environment variables from .env
source .env

# set env variables
export ADDRESSES_FILE=./deployments/polygon.json
export RPC_URL=$RPC_URL_POLYGON

# load common utilities
. $(dirname $0)/../common.sh

# deploy contracts
factory_address=$(deployViaCast UniswapV3xPYTFactory 'constructor(address,address)' $UNIV3_FACTORY $UNIV3_QUOTER)
echo "UniswapV3xPYTFactory=$factory_address"