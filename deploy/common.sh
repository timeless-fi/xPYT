ADDRESSES_FILE=${ADDRESSES_FILE:-./deployments/output.json}
RPC_URL=${RPC_URL:-http://localhost:8545}

deploy() {
	NAME=$1
	ARGS=${@:2}

	ADDRESS=$(forge create $NAME --json --rpc-url=$RPC_URL --private-key=$PRIVATE_KEY --constructor-args $ARGS | jq -r '.deployedTo')
	saveContract "$NAME" "$ADDRESS"
	echo "$ADDRESS"
}

saveContract() {
	# create an empty json if it does not exist
	if [[ ! -e $ADDRESSES_FILE ]]; then
		echo "{}" >"$ADDRESSES_FILE"
	fi
	result=$(cat "$ADDRESSES_FILE" | jq -r ". + {\"$1\": \"$2\"}")
	printf %s "$result" >"$ADDRESSES_FILE"
}