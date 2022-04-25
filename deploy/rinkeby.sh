# load environment variables from .env
source .env

# set env variables
export ADDRESSES_FILE=./deployments/rinkeby.json
export RPC_URL=$RPC_URL_RINKEBY

# load common utilities
. $(dirname $0)/common.sh

# deploy contracts
factory_address=$(deploy xPYTFactory $UNIV3_FACTORY $UNIV3_QUOTER)
echo "xPYTFactory=$factory_address"