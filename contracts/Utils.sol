pragma solidity 0.5.10;

import "./lib/math/SafeMath.sol";

interface ERC20 {
    function balanceOf(address account) external view returns (uint256);
}

interface MarketDapp {
    // Returns the address to approve tokens for
    function tokenReceiver(address[] calldata assetIds, uint256[] calldata dataValues, address[] calldata addresses) external view returns(address);
    function trade(address[] calldata assetIds, uint256[] calldata dataValues, address[] calldata addresses, address payable recipient) external payable;
}

/// @title Util functions for the BrokerV2 contract for Switcheo Exchange
/// @author Switcheo Network
/// @notice Functions were moved from the BrokerV2 contract into this contract
/// so that the BrokerV2 contract would not exceed the maximum contract size of
/// 24 KB.
library Utils {
    using SafeMath for uint256;

    // The constants for EIP-712 are precompiled to reduce contract size,
    // the original values are left here for reference and verification.
    //
    // bytes32 public constant EIP712_DOMAIN_TYPEHASH = keccak256(abi.encodePacked(
    //     "EIP712Domain(",
    //         "string name,",
    //         "string version,",
    //         "uint256 chainId,",
    //         "address verifyingContract,",
    //         "bytes32 salt",
    //     ")"
    // ));
    // bytes32 public constant EIP712_DOMAIN_TYPEHASH = 0xd87cd6ef79d4e2b95e15ce8abf732db51ec771f1ca2edccf22a46c729ac56472;
    //
    // bytes32 public constant CONTRACT_NAME = keccak256("Switcheo Exchange");
    // bytes32 public constant CONTRACT_VERSION = keccak256("2");
    // uint256 public constant CHAIN_ID = 3; // TODO: Update this before deploying
    // address public constant VERIFYING_CONTRACT = address(1); // TODO: Update this before deploying
    // bytes32 public constant SALT = keccak256("switcheo-eth-salt");

    // bytes32 public constant DOMAIN_SEPARATOR = keccak256(abi.encode(
    //     EIP712_DOMAIN_TYPEHASH,
    //     CONTRACT_NAME,
    //     CONTRACT_VERSION,
    //     CHAIN_ID,
    //     VERIFYING_CONTRACT,
    //     SALT
    // ));
    bytes32 public constant DOMAIN_SEPARATOR = 0x14f697e312cdba1c10a1eb5c87d96fa22b63aef9dc39592568387471319ea630;

    // bytes32 public constant OFFER_TYPEHASH = keccak256(abi.encodePacked(
    //     "Offer(",
    //         "address maker,",
    //         "address offerAssetId,",
    //         "uint256 offerAmount,",
    //         "address wantAssetId,",
    //         "uint256 wantAmount,",
    //         "address feeAssetId,",
    //         "uint256 feeAmount,",
    //         "uint256 nonce",
    //     ")"
    // ));
    bytes32 public constant OFFER_TYPEHASH = 0xf845c83a8f7964bc8dd1a092d28b83573b35be97630a5b8a3b8ae2ae79cd9260;

    // bytes32 public constant FILL_TYPEHASH = keccak256(abi.encodePacked(
    //     "Fill(",
    //         "address filler,",
    //         "address offerAssetId,",
    //         "uint256 offerAmount,",
    //         "address wantAssetId,",
    //         "uint256 wantAmount,",
    //         "address feeAssetId,",
    //         "uint256 feeAmount,",
    //         "uint256 nonce",
    //     ")"
    // ));
    bytes32 public constant FILL_TYPEHASH = 0x5f59dbc3412a4575afed909d028055a91a4250ce92235f6790c155a4b2669e99;

    // The Ether token address is set as the constant 0x00 for backwards
    // compatibility
    address private constant ETHER_ADDR = address(0);

    uint256 private constant mask8 = ~(~uint256(0) << 8);
    uint256 private constant mask16 = ~(~uint256(0) << 16);
    uint256 private constant mask24 = ~(~uint256(0) << 24);
    uint256 private constant mask32 = ~(~uint256(0) << 32);
    uint256 private constant mask40 = ~(~uint256(0) << 40);
    uint256 private constant mask48 = ~(~uint256(0) << 48);
    uint256 private constant mask56 = ~(~uint256(0) << 56);
    uint256 private constant mask128 = ~(~uint256(0) << 128);

    event Trade(
        address maker,
        address taker,
        address makerGiveAsset,
        uint256 makerGiveAmount,
        address fillerGiveAsset,
        uint256 fillerGiveAmount
    );

    /// @dev Validates `BrokerV2.trade` parameters to ensure trade fairness,
    /// see `BrokerV2.trade` for param details.
    /// @param _values Values from `trade`
    /// @param _hashes Hashes from `trade`
    /// @param _addresses Addresses from `trade`
    function validateTrades(
        uint256[] memory _values,
        bytes32[] memory _hashes,
        address[] memory _addresses
    )
        public
        returns (bytes32[] memory)
    {
        _validateTradeInputLengths(_values, _hashes);
        _validateUniqueOffers(_values);
        _validateMatches(_values, _addresses);
        _validateFillAmounts(_values);
        _validateTradeData(_values, _addresses);

        // validate signatures of all fills
        _validateTradeSignatures(
            _values,
            _hashes,
            _addresses,
            FILL_TYPEHASH,
            _values[0] & mask8, // numOffers
            (_values[0] & mask8) + ((_values[0] & mask16) >> 8) // numOffers + numFills
        );

        _emitTradeEvents(_values, _addresses, new address[](0), false);

        // validate signatures of all offers
        return _validateTradeSignatures(
            _values,
            _hashes,
            _addresses,
            OFFER_TYPEHASH,
            0,
            _values[0] & mask8 // numOffers
        );
    }

    /// @dev Validates `BrokerV2.networkTrade` parameters to ensure trade fairness,
    /// see `BrokerV2.networkTrade` for param details.
    /// @param _values Values from `networkTrade`
    /// @param _hashes Hashes from `networkTrade`
    /// @param _addresses Addresses from `networkTrade`
    /// @param _operator Address of the `BrokerV2.operator`
    function validateNetworkTrades(
        uint256[] memory _values,
        bytes32[] memory _hashes,
        address[] memory _addresses,
        address _operator
    )
        public
        pure
        returns (bytes32[] memory)
    {
        _validateNetworkTradeInputLengths(_values, _hashes);
        _validateUniqueOffers(_values);
        _validateNetworkMatches(_values, _addresses, _operator);
        _validateOfferData(_values, _addresses, _operator);

        // validate signatures of all offers
        return _validateTradeSignatures(
            _values,
            _hashes,
            _addresses,
            OFFER_TYPEHASH,
            0,
            _values[0] & mask8 // numOffers
        );
    }

    /// @dev Executes trades against external markets,
    /// see `BrokerV2.networkTrade` for param details.
    /// @param _values Values from `networkTrade`
    /// @param _addresses Addresses from `networkTrade`
    /// @param _marketDapps See `BrokerV2.marketDapps`
    function performNetworkTrades(
        uint256[] memory _values,
        address[] memory _addresses,
        address[] memory _marketDapps
    )
        public
        returns (uint256[] memory)
    {
        uint256[] memory increments = new uint256[](_addresses.length / 2);
        // i = 1 + numOffers * 2
        uint256 i = 1 + (_values[0] & mask8) * 2;
        uint256 end = _values.length;

        // loop matches
        for(i; i < end; i++) {
            uint256[] memory data = new uint256[](9);
            data[0] = _values[i]; // match data
            data[1] = data[0] & mask8; // offerIndex
            data[2] = (data[0] & mask24) >> 16; // operator.surplusAssetIndex
            data[3] = _values[data[1] * 2 + 1]; // offer.dataA
            data[4] = _values[data[1] * 2 + 2]; // offer.dataB
            data[5] = ((data[3] & mask16) >> 8); // maker.offerAssetIndex
            data[6] = ((data[3] & mask24) >> 16); // maker.wantAssetIndex
            // amount of offerAssetId to take from offer is equal to the match.takeAmount
            data[7] = data[0] >> 128;
            // expected amount to receive is: matchData.takeAmount * offer.wantAmount / offer.offerAmount
            data[8] = data[7].mul(data[4] >> 128).div(data[4] & mask128);

            address[] memory assetIds = new address[](3);
            assetIds[0] = _addresses[data[5] * 2 + 1]; // offer.offerAssetId
            assetIds[1] = _addresses[data[6] * 2 + 1]; // offer.wantAssetId
            assetIds[2] = _addresses[data[2] * 2 + 1]; // surplusAssetId

            uint256[] memory dataValues = new uint256[](3);
            dataValues[0] = data[7]; // the proportion of offerAmount to offer
            dataValues[1] = data[8]; // the propotionate wantAmount of the offer
            dataValues[2] = data[0]; // match data

            increments[data[2]] = _performNetworkTrade(
                assetIds,
                dataValues,
                _marketDapps,
                _addresses
            );
        }

        _emitTradeEvents(_values, _addresses, _marketDapps, true);

        return increments;
    }

    /// @notice Approves a token transfer
    /// @param _assetId The address of the token to approve
    /// @param _spender The address of the spender to approve
    /// @param _amount The number of tokens to approve
    function approveTokenTransfer(
        address _assetId,
        address _spender,
        uint256 _amount
    )
        public
    {
        _validateContractAddress(_assetId);

        // Some tokens have an `approve` which returns a boolean and some do not.
        // The ERC20 interface cannot be used here because it requires specifying
        // an explicit return value, and an EVM exception would be raised when calling
        // a token with the mismatched return value.
        bytes memory payload = abi.encodeWithSignature(
            "approve(address,uint256)",
            _spender,
            _amount
        );
        bytes memory returnData = _callContract(_assetId, payload);
        // Ensure that the asset transfer succeeded
        _validateContractCallResult(returnData);
    }

    /// @notice Transfers tokens into the contract
    /// @param _user The address to transfer the tokens from
    /// @param _assetId The address of the token to transfer
    /// @param _amount The number of tokens to transfer
    /// @param _expectedAmount The number of tokens expected to be received,
    /// this may not match `_amount`, for example, tokens which have a
    /// propotion burnt on transfer will have a different amount received.
    function transferTokensIn(
        address _user,
        address _assetId,
        uint256 _amount,
        uint256 _expectedAmount
    )
        public
    {
        _validateContractAddress(_assetId);

        uint256 initialBalance = tokenBalance(_assetId);

        // Some tokens have a `transferFrom` which returns a boolean and some do not.
        // The ERC20 interface cannot be used here because it requires specifying
        // an explicit return value, and an EVM exception would be raised when calling
        // a token with the mismatched return value.
        bytes memory payload = abi.encodeWithSignature(
            "transferFrom(address,address,uint256)",
            _user,
            address(this),
            _amount
        );
        bytes memory returnData = _callContract(_assetId, payload);
        // Ensure that the asset transfer succeeded
        _validateContractCallResult(returnData);

        uint256 finalBalance = tokenBalance(_assetId);
        uint256 transferredAmount = finalBalance.sub(initialBalance);

        require(transferredAmount == _expectedAmount, "Invalid transfer");
    }

    /// @notice Transfers tokens from the contract to a user
    /// @param _receivingAddress The address to transfer the tokens to
    /// @param _assetId The address of the token to transfer
    /// @param _amount The number of tokens to transfer
    function transferTokensOut(
        address _receivingAddress,
        address _assetId,
        uint256 _amount
    )
        public
    {
        _validateContractAddress(_assetId);

        // Some tokens have a `transfer` which returns a boolean and some do not.
        // The ERC20 interface cannot be used here because it requires specifying
        // an explicit return value, and an EVM exception would be raised when calling
        // a token with the mismatched return value.
        bytes memory payload = abi.encodeWithSignature(
                                   "transfer(address,uint256)",
                                   _receivingAddress,
                                   _amount
                               );
        bytes memory returnData = _callContract(_assetId, payload);

        // Ensure that the asset transfer succeeded
        _validateContractCallResult(returnData);
    }

    /// @notice Returns the number of tokens owned by this contract
    /// @param _assetId The address of the token to query
    function externalBalance(address _assetId) public view returns (uint256) {
        if (_assetId == ETHER_ADDR) {
            return address(this).balance;
        }
        return tokenBalance(_assetId);
    }

    /// @notice Returns the number of tokens owned by this contract.
    /// @dev This will not work for Ether tokens, use `externalBalance` for
    /// Ether tokens.
    /// @param _assetId The address of the token to query
    function tokenBalance(address _assetId) public view returns (uint256) {
        return ERC20(_assetId).balanceOf(address(this));
    }

    /// @dev Validates that the specified `_hash` was signed by the specified `_user`.
    /// This method supports the EIP712 specification, the older Ethereum
    /// signed message specification is also supported for backwards compatibility.
    /// @param _hash The original hash that was signed by the user
    /// @param _user The user who signed the hash
    /// @param _v The `v` component of the `_user`'s signature
    /// @param _r The `r` component of the `_user`'s signature
    /// @param _s The `s` component of the `_user`'s signature
    /// @param _prefixed If true, the signature will be verified
    /// against the Ethereum signed message specification instead of the
    /// EIP712 specification
    function validateSignature(
        bytes32 _hash,
        address _user,
        uint8 _v,
        bytes32 _r,
        bytes32 _s,
        bool _prefixed
    )
        public
        pure
    {
        bytes32 eip712Hash = keccak256(abi.encodePacked(
            "\x19\x01",
            DOMAIN_SEPARATOR,
            _hash
        ));

        if (_prefixed) {
            bytes32 prefixedHash = keccak256(abi.encodePacked(
                "\x19Ethereum Signed Message:\n32",
                eip712Hash
            ));
            require(_user == ecrecover(prefixedHash, _v, _r, _s), "Invalid signature");
        } else {
            require(_user == ecrecover(eip712Hash, _v, _r, _s), "Invalid signature");
        }
    }

    /// @dev Ensures that `_address` is not the zero address
    /// @param _address The address to check
    function validateAddress(address _address) public pure {
        require(_address != address(0), "Invalid address");
    }

    function _emitTradeEvents(
        uint256[] memory _values,
        address[] memory _addresses,
        address[] memory _marketDapps,
        bool _forNetworkTrade
    )
        private
    {
        uint256 i = 1;
        // i += numOffers * 2
        i += (_values[0] & mask8) * 2;
        // i += numFills * 2
        i += ((_values[0] & mask16) >> 8) * 2;

        uint256 end = _values.length;

        // loop matches
        for(i; i < end; i++) {
            uint256[] memory data = new uint256[](7);
            data[0] = _values[i] & mask8; // match.offerIndex
            data[1] = _values[1 + data[0] * 2] & mask8; // makerIndex
            data[2] = (_values[1 + data[0] * 2] & mask16) >> 8; // makerOfferAssetIndex
            data[3] = (_values[1 + data[0] * 2] & mask24) >> 16; // makerWantAssetIndex
            data[4] = _values[i] >> 128; // match.takeAmount
            // receiveAmount = match.takeAmount * offer.wantAmount / offer.offerAmount
            data[5] = data[4].mul(_values[2 + data[0] * 2] >> 128)
                             .div(_values[2 + data[0] * 2] & mask128);
            // match.fillIndex for `trade`, marketDappIndex for `networkTrade`
            data[6] = (_values[i] & mask16) >> 8;

            address filler;
            if (_forNetworkTrade) {
                filler = _marketDapps[data[6]];
            } else {
                uint256 fillerIndex = (_values[1 + data[6] * 2] & mask8);
                filler = _addresses[fillerIndex * 2];
            }

            emit Trade(
                _addresses[data[1] * 2], // maker
                filler,
                _addresses[data[2] * 2 + 1], // makerGiveAsset
                data[4], // makerGiveAmount
                _addresses[data[3] * 2 + 1], // fillerGiveAsset
                data[5] // fillerGiveAmount
            );
        }
    }


    /// @notice Executes a trade against an external market.
    /// @dev The initial Ether or token balance is compared with the
    /// balance after the trade to ensure that the appropriate amounts of
    /// tokens were taken and an appropriate amount received.
    /// The trade will fail if the number of tokens received is less than
    /// expected. If the number of tokens received is more than expected than
    /// the excess tokens are transferred to the `BrokerV2.operator`.
    /// @param _assetIds[0] The offerAssetId of the offer
    /// @param _assetIds[1] The wantAssetId of the offer
    /// @param _assetIds[2] The surplusAssetId
    /// @param _dataValues[0] The number of tokens offerred
    /// @param _dataValues[1] The number of tokens expected to be received
    /// @param _dataValues[2] Match data
    /// @param _marketDapps See `BrokerV2.marketDapps`
    /// @param _addresses Addresses from `networkTrade`
    function _performNetworkTrade(
        address[] memory _assetIds,
        uint256[] memory _dataValues,
        address[] memory _marketDapps,
        address[] memory _addresses
    )
        private
        returns (uint256)
    {
        uint256 dappIndex = (_dataValues[2] & mask16) >> 8;
        MarketDapp marketDapp = MarketDapp(_marketDapps[dappIndex]);

        uint256[] memory funds = new uint256[](6);
        funds[0] = externalBalance(_assetIds[0]); // initialOfferTokenBalance
        funds[1] = externalBalance(_assetIds[1]); // initialWantTokenBalance
        if (_assetIds[2] != _assetIds[0] && _assetIds[2] != _assetIds[1]) {
            funds[2] = externalBalance(_assetIds[2]); // initialSurplusTokenBalance
        }

        uint256 ethValue = 0;
        address tokenReceiver;

        if (_assetIds[0] != ETHER_ADDR) {
            tokenReceiver = marketDapp.tokenReceiver(_assetIds, _dataValues, _addresses);
            approveTokenTransfer(
                _assetIds[0], // offerAssetId
                tokenReceiver,
                _dataValues[0] // offerAmount
            );
        } else {
            ethValue = _dataValues[0]; // offerAmount
        }

        marketDapp.trade.value(ethValue)(
            _assetIds,
            _dataValues,
            _addresses,
            // use uint160 to cast `address` to `address payable`
            address(uint160(address(this))) // destAddress
        );

        funds[3] = externalBalance(_assetIds[0]); // finalOfferTokenBalance
        funds[4] = externalBalance(_assetIds[1]); // finalWantTokenBalance
        if (_assetIds[2] != _assetIds[0] && _assetIds[2] != _assetIds[1]) {
            funds[5] = externalBalance(_assetIds[2]); // finalSurplusTokenBalance
        }

        uint256 surplusAmount = 0;

        // validate that the appropriate offerAmount was deducted
        // surplusAssetId == offerAssetId
        if (_assetIds[2] == _assetIds[0]) {
            // surplusAmount = finalOfferTokenBalance - (initialOfferTokenBalance - offerAmount)
            surplusAmount = funds[3].sub(funds[0].sub(_dataValues[0]));
        } else {
            // finalOfferTokenBalance == initialOfferTokenBalance - offerAmount
            require(funds[3] == funds[0].sub(_dataValues[0]), "Invalid offer asset balance");
        }

        // validate that the appropriate wantAmount was credited
        // surplusAssetId == wantAssetId
        if (_assetIds[2] == _assetIds[1]) {
            // surplusAmount = finalWantTokenBalance - (initialWantTokenBalance + wantAmount)
            surplusAmount = funds[4].sub(funds[1].add(_dataValues[1]));
        } else {
            // finalWantTokenBalance == initialWantTokenBalance + wantAmount
            require(funds[4] == funds[1].add(_dataValues[1]), "Invalid want asset balance");
        }

        // surplusAssetId != offerAssetId && surplusAssetId != wantAssetId
        if (_assetIds[2] != _assetIds[0] && _assetIds[2] != _assetIds[1]) {
            // surplusAmount = finalSurplusTokenBalance - initialSurplusTokenBalance
            surplusAmount = funds[5].sub(funds[2]);
        }

        // set the approved token amount back to zero
        if (_assetIds[0] != ETHER_ADDR) {
            approveTokenTransfer(
                _assetIds[0],
                tokenReceiver,
                0
            );
        }

        return surplusAmount;
    }

    /// @dev Validates input lengths based on the expected format
    /// detailed in the `trade` method.
    /// @param _values Values from `trade`
    /// @param _hashes Hashes from `trade`
    function _validateTradeInputLengths(
        uint256[] memory _values,
        bytes32[] memory _hashes
    )
        private
        pure
    {
        uint256 numOffers = _values[0] & mask8;
        uint256 numFills = (_values[0] & mask16) >> 8;
        uint256 numMatches = (_values[0] & mask24) >> 16;

        // Validate that bits(24..256) are zero
        require(_values[0] >> 24 == 0, "Invalid trade input");

        // It is enforced by other checks that if a fill is present
        // then it must be completely filled so there must be at least one offer
        // and at least one match in this case.
        // It is possible to have one offer with no matches and no fills
        // but that is blocked by this check as there is no foreseeable use
        // case for it.
        require(
            numOffers > 0 && numFills > 0 && numMatches > 0,
            "Invalid trade input"
        );

        require(
            _values.length == 1 + numOffers * 2 + numFills * 2 + numMatches,
            "Invalid _values.length"
        );

        require(
            _hashes.length == (numOffers + numFills) * 2,
            "Invalid _hashes.length"
        );
    }

    /// @dev Validates input lengths based on the expected format
    /// detailed in the `networkTrade` method.
    /// @param _values Values from `networkTrade`
    /// @param _hashes Hashes from `networkTrade`
    function _validateNetworkTradeInputLengths(
        uint256[] memory _values,
        bytes32[] memory _hashes
    )
        private
        pure
    {
        uint256 numOffers = _values[0] & mask8;
        uint256 numFills = (_values[0] & mask16) >> 8;
        uint256 numMatches = (_values[0] & mask24) >> 16;

        // Validate that bits(24..256) are zero
        require(_values[0] >> 24 == 0, "Invalid networkTrade input");

        // Validate that numFills is zero because the offers
        // should be filled against external orders
        require(
            numOffers > 0 && numMatches > 0 && numFills == 0,
            "Invalid networkTrade input"
        );

        require(
            _values.length == 1 + numOffers * 2 + numFills * 2 + numMatches,
            "Invalid _values.length"
        );

        require(
            _hashes.length == (numOffers + numFills) * 2,
            "Invalid _hashes.length"
        );
    }

    /// @dev See the `BrokerV2.trade` method for an explanation of why offer
    /// uniquness is required.
    /// The set of offers in `_values` must be sorted such that offer nonces'
    /// are arranged in a strictly ascending order.
    /// This allows the validation of offer uniqueness to be done in O(N) time,
    /// with N being the number of offers.
    /// @param _values Values from `trade`
    function _validateUniqueOffers(uint256[] memory _values) private pure {
        uint256 numOffers = _values[0] & mask8;

        uint256 prevNonce;

        for(uint256 i = 0; i < numOffers; i++) {
            uint256 nonce = (_values[i * 2 + 1] & mask128) >> 56;

            if (i == 0) {
                // Set the value of the first nonce
                prevNonce = nonce;
                continue;
            }

            require(nonce > prevNonce, "Invalid offer nonces");
            prevNonce = nonce;
        }
    }

    /// @dev Validate that for every match:
    /// 1. offerIndexes fall within the range of offers
    /// 2. fillIndexes falls within the range of fills
    /// 3. offer.offerAssetId == fill.wantAssetId
    /// 4. offer.wantAssetId == fill.offerAssetId
    /// 5. takeAmount > 0
    /// 6. (offer.wantAmount * takeAmount) % offer.offerAmount == 0
    /// @param _values Values from `trade`
    /// @param _addresses Addresses from `trade`
    function _validateMatches(
        uint256[] memory _values,
        address[] memory _addresses
    )
        private
        pure
    {
        uint256 numOffers = _values[0] & mask8;
        uint256 numFills = (_values[0] & mask16) >> 8;

        uint256 i = 1 + numOffers * 2 + numFills * 2;
        uint256 end = _values.length;

        // loop matches
        for (i; i < end; i++) {
            uint256 offerIndex = _values[i] & mask8;
            uint256 fillIndex = (_values[i] & mask16) >> 8;

            require(offerIndex < numOffers, "Invalid match.offerIndex");

            require(fillIndex >= numOffers && fillIndex < numOffers + numFills, "Invalid match.fillIndex");

            uint256 makerOfferAssetIndex = (_values[1 + offerIndex * 2] & mask16) >> 8;
            uint256 makerWantAssetIndex = (_values[1 + offerIndex * 2] & mask24) >> 16;
            uint256 fillerOfferAssetIndex = (_values[1 + fillIndex * 2] & mask16) >> 8;
            uint256 fillerWantAssetIndex = (_values[1 + fillIndex * 2] & mask24) >> 16;

            require(
                _addresses[makerOfferAssetIndex * 2 + 1] == _addresses[fillerWantAssetIndex * 2 + 1],
                "offer.offerAssetId does not match fill.wantAssetId"
            );

            require(
                _addresses[makerWantAssetIndex * 2 + 1] == _addresses[fillerOfferAssetIndex * 2 + 1],
                "offer.wantAssetId does not match fill.offerAssetId"
            );

            // require that bits(16..128) are all zero for every match
            require((_values[i] & mask128) >> 16 == uint256(0), "Invalid match data");

            uint256 takeAmount = _values[i] >> 128;
            require(takeAmount > 0, "Invalid match.takeAmount");

            uint256 offerDataB = _values[2 + offerIndex * 2];
            // (offer.wantAmount * takeAmount) % offer.offerAmount == 0
            require(
                (offerDataB >> 128).mul(takeAmount).mod(offerDataB & mask128) == 0,
                "Invalid amounts"
            );
        }
    }

    /// @dev Validate that for every match:
    /// 1. offerIndexes fall within the range of offers
    /// 2. _addresses[surplusAssetIndexes * 2] matches the operator address
    /// 3. takeAmount > 0
    /// 4. (offer.wantAmount * takeAmount) % offer.offerAmount == 0
    /// @param _values Values from `trade`
    /// @param _addresses Addresses from `trade`
    /// @param _operator Address of the `BrokerV2.operator`
    function _validateNetworkMatches(
        uint256[] memory _values,
        address[] memory _addresses,
        address _operator
    )
        private
        pure
    {
        uint256 numOffers = _values[0] & mask8;

        // 1 + numOffers * 2
        uint256 i = 1 + (_values[0] & mask8) * 2;
        uint256 end = _values.length;

        // loop matches
        for (i; i < end; i++) {
            uint256 offerIndex = _values[i] & mask8;
            uint256 surplusAssetIndex = (_values[i] & mask24) >> 16;

            require(offerIndex < numOffers, "Invalid match.offerIndex");
            require(_addresses[surplusAssetIndex * 2] == _operator, "Invalid operator address");

            uint256 takeAmount = _values[i] >> 128;
            require(takeAmount > 0, "Invalid match.takeAmount");

            uint256 offerDataB = _values[2 + offerIndex * 2];
            // (offer.wantAmount * takeAmount) % offer.offerAmount == 0
            require(
                (offerDataB >> 128).mul(takeAmount).mod(offerDataB & mask128) == 0,
                "Invalid amounts"
            );
        }
    }

    /// @dev Validate that all fills will be completely filled by the specified
    /// matches. See the `BrokerV2.trade` method for an explanation of why
    /// fills must be completely filled.
    /// @param _values Values from `trade`
    function _validateFillAmounts(uint256[] memory _values) private pure {
        // "filled" is used to store the sum of `takeAmount`s and `giveAmount`s.
        // While a fill's `offerAmount` and `wantAmount` are combined to share
        // a single uint256 value, each sum of `takeAmount`s and `giveAmount`s
        // for a fill is tracked with an individual uint256 value.
        // This is to prevent the verification from being vulnerable to overflow
        // issues.
        uint256[] memory filled = new uint256[](_values.length);

        uint256 i = 1;
        // i += numOffers * 2
        i += (_values[0] & mask8) * 2;
        // i += numFills * 2
        i += ((_values[0] & mask16) >> 8) * 2;

        uint256 end = _values.length;

        // loop matches
        for (i; i < end; i++) {
            uint256 offerIndex = _values[i] & mask8;
            uint256 fillIndex = (_values[i] & mask16) >> 8;
            uint256 takeAmount = _values[i] >> 128;
            uint256 wantAmount = _values[2 + offerIndex * 2] >> 128;
            uint256 offerAmount = _values[2 + offerIndex * 2] & mask128;
            // giveAmount = takeAmount * wantAmount / offerAmount
            uint256 giveAmount = takeAmount.mul(wantAmount).div(offerAmount);

            // (1 + fillIndex * 2) would give the index of the first part
            // of the data for the fill at fillIndex within `_values`,
            // and (2 + fillIndex * 2) would give the index of the second part
            filled[1 + fillIndex * 2] = filled[1 + fillIndex * 2].add(giveAmount);
            filled[2 + fillIndex * 2] = filled[2 + fillIndex * 2].add(takeAmount);
        }

        // numOffers
        i = _values[0] & mask8;
        // i + numFills
        end = i + ((_values[0] & mask16) >> 8);

        // loop fills
        for(i; i < end; i++) {
            require(
                // fill.offerAmount == (sum of given amounts for fill)
                _values[i * 2 + 2] & mask128 == filled[i * 2 + 1] &&
                // fill.wantAmount == (sum of taken amounts for fill)
                _values[i * 2 + 2] >> 128 == filled[i * 2 + 2],
                "Invalid fills"
            );
        }
    }

    /// @dev Validates that for every offer / fill:
    /// 1. offerAssetId != wantAssetId
    /// 2. offerAmount > 0 && wantAmount > 0
    /// 3. The referenced `operator` address is the zero address
    /// @param _values Values from `trade`
    /// @param _addresses Addresses from `trade`
    function _validateTradeData(
        uint256[] memory _values,
        address[] memory _addresses
    )
        private
        pure
    {
        // numOffers + numFills
        uint256 end = (_values[0] & mask8) +
                      ((_values[0] & mask16) >> 8);

        for (uint256 i = 0; i < end; i++) {
            uint256 dataA = _values[i * 2 + 1];
            uint256 dataB = _values[i * 2 + 2];

            require(
                // offerAssetId != wantAssetId
                _addresses[((dataA & mask16) >> 8) * 2 + 1] !=
                _addresses[((dataA & mask24) >> 16) * 2 + 1],
                "Invalid trade assets"
            );

            require(
                // offerAmount > 0 && wantAmount > 0
                (dataB & mask128) > 0 && (dataB >> 128) > 0,
                "Invalid trade amounts"
            );

             require(
                // _addresses[operator address index] == address(0)
                // The actual operator address will be read directly from
                // the contract's storage
                _addresses[((dataA & mask40) >> 32) * 2] == address(0),
                "Invalid operator address placeholder"
            );

             require(
                // _addresses[operator fee asset ID index] == address(1)
                // address(1) is used to differentiate from the ETHER_ADDR which is address(0)
                // The actual fee asset ID will be read from the filler / maker feeAssetId
                _addresses[((dataA & mask40) >> 32) * 2 + 1] == address(1),
                "Invalid operator fee asset ID placeholder"
            );
        }
    }

    /// @dev Validates that for every offer
    /// 1. offerAssetId != wantAssetId
    /// 2. offerAmount > 0 && wantAmount > 0
    /// 3. Specified `operator` address matches the expected `operator` address,
    /// 4. Specified `operator.feeAssetId` matches the offer's feeAssetId
    /// @param _values Values from `trade`
    /// @param _addresses Addresses from `trade`
    function _validateOfferData(
        uint256[] memory _values,
        address[] memory _addresses,
        address _operator
    )
        private
        pure
    {
        // numOffers
        uint256 end = _values[0] & mask8;

        for (uint256 i = 0; i < end; i++) {
            uint256 dataA = _values[i * 2 + 1];
            uint256 dataB = _values[i * 2 + 2];
            uint256 feeAssetIndex = ((dataA & mask40) >> 32) * 2;

            require(
                // offerAssetId != wantAssetId
                _addresses[((dataA & mask16) >> 8) * 2 + 1] !=
                _addresses[((dataA & mask24) >> 16) * 2 + 1],
                "Invalid trade assets"
            );

            require(
                // offerAmount > 0 && wantAmount > 0
                (dataB & mask128) > 0 && (dataB >> 128) > 0,
                "Invalid trade amounts"
            );

             require(
                _addresses[feeAssetIndex] == _operator,
                "Invalid operator address"
            );

             require(
                _addresses[feeAssetIndex + 1] == _addresses[((dataA & mask32) >> 24) * 2 + 1],
                "Invalid operator fee asset ID"
            );
        }
    }

    /// @dev Validates signatures for a set of offers or fills
    /// @param _values Values from `trade`
    /// @param _hashes Hashes from `trade`
    /// @param _addresses Addresses from `trade`
    /// @param _typehash The typehash used to construct the signed hash
    /// @param _i The starting index to verify
    /// @param _end The ending index to verify
    /// @return An array of hash keys if _i started as 0, because only
    /// the hash keys of offers are needed
    function _validateTradeSignatures(
        uint256[] memory _values,
        bytes32[] memory _hashes,
        address[] memory _addresses,
        bytes32 _typehash,
        uint256 _i,
        uint256 _end
    )
        private
        pure
        returns (bytes32[] memory)
    {
        bytes32[] memory hashKeys;
        if (_i == 0) {
            hashKeys = new bytes32[](_end - _i);
        }

        for (_i; _i < _end; _i++) {
            uint256 dataA = _values[_i * 2 + 1];
            uint256 dataB = _values[_i * 2 + 2];

            bytes32 hashKey = keccak256(abi.encode(
                _typehash,
                _addresses[(dataA & mask8) * 2], // user
                _addresses[((dataA & mask16) >> 8) * 2 + 1], // offerAssetId
                dataB & mask128, // offerAmount
                _addresses[((dataA & mask24) >> 16) * 2 + 1], // wantAssetId
                dataB >> 128, // wantAmount
                _addresses[((dataA & mask32) >> 24) * 2 + 1], // feeAssetId
                dataA >> 128, // feeAmount
                (dataA & mask128) >> 56 // nonce
            ));

            bool prefixedSignature = ((dataA & mask56) >> 48) != 0;

            validateSignature(
                hashKey,
                _addresses[(dataA & mask8) * 2], // user
                uint8((dataA & mask48) >> 40), // The `v` component of the user's signature
                _hashes[_i * 2], // The `r` component of the user's signature
                _hashes[_i * 2 + 1], // The `s` component of the user's signature
                prefixedSignature
            );

            if (hashKeys.length > 0) { hashKeys[_i] = hashKey; }
        }

        return hashKeys;
    }

    /// @dev Ensure that the address is a deployed contract
    /// @param _contract The address to check
    function _validateContractAddress(address _contract) private view {
        assembly {
            if iszero(extcodesize(_contract)) { revert(0, 0) }
        }
    }

    /// @dev A thin wrapper around the native `call` function, to
    /// validate that the contract `call` must be successful.
    /// See https://solidity.readthedocs.io/en/v0.5.1/050-breaking-changes.html
    /// for details on constructing the `_payload`
    /// @param _contract Address of the contract to call
    /// @param _payload The data to call the contract with
    /// @return The data returned from the contract call
    function _callContract(
        address _contract,
        bytes memory _payload
    )
        private
        returns (bytes memory)
    {
        bool success;
        bytes memory returnData;

        (success, returnData) = _contract.call(_payload);
        require(success, "Contract call failed");

        return returnData;
    }

    /// @dev Fix for ERC-20 tokens that do not have proper return type
    /// See: https://github.com/ethereum/solidity/issues/4116
    /// https://medium.com/loopring-protocol/an-incompatibility-in-smart-contract-threatening-dapp-ecosystem-72b8ca5db4da
    /// https://github.com/sec-bit/badERC20Fix/blob/master/badERC20Fix.sol
    /// @param _data The data returned from a transfer call
    function _validateContractCallResult(bytes memory _data) private pure {
        require(
            _data.length == 0 ||
            (_data.length == 32 && _getUint256FromBytes(_data) != 0),
            "Invalid contract call result"
        );
    }

    /// @dev Converts data of type `bytes` into its corresponding `uint256` value
    /// @param _data The data in bytes
    /// @return The corresponding `uint256` value
    function _getUint256FromBytes(
        bytes memory _data
    )
        private
        pure
        returns (uint256)
    {
        uint256 parsed;
        assembly { parsed := mload(add(_data, 32)) }
        return parsed;
    }
}
