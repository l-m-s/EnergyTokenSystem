pragma solidity ^0.7.0;

import "./Commons.sol";
import "./IdentityContractFactory.sol";
import "./ClaimVerifier.sol";
import "./IEnergyToken.sol";
import "./EnergyTokenLib.sol";
import "./../dependencies/erc-1155/contracts/ERC1155.sol";
import "./IERC165.sol";

contract EnergyToken is ERC1155, IEnergyToken, IERC165 {
    using SafeMath for uint256;
    using Address for address;

    enum PlantType {Generation, Consumption}

    event EnergyDocumented(PlantType plantType, uint256 value, address indexed plant, bool corrected, uint64 indexed balancePeriod, address indexed meteringAuthority);
    event ForwardsCreated(TokenKind tokenKind, uint64 balancePeriod, Distributor distributor, uint256 id);
    
    // id => whetherCreated
    mapping (uint256 => bool) createdGenerationBasedForwards;
    
    IdentityContract public marketAuthority;

    mapping(address => mapping(uint64 => EnergyTokenLib.EnergyDocumentation)) public energyDocumentations;
    mapping(uint64 => mapping(address => uint256)) public energyConsumedRelevantForGenerationPlant;
    mapping(uint64 => mapping(address => address[])) relevantGenerationPlantsForConsumptionPlant;
    mapping(uint64 => mapping(address => uint256)) public numberOfRelevantConsumptionPlantsUnmeasuredForGenerationPlant;
    mapping(uint64 => mapping(address => uint256)) public numberOfRelevantConsumptionPlantsForGenerationPlant;
    mapping(uint256 => Distributor) public id2Distributor;
    mapping(uint64 => mapping(address => EnergyTokenLib.ForwardKindOfGenerationPlant)) forwardKindOfGenerationPlant;
    
    bool reentrancyLock;
    modifier noReentrancy {
        require(!reentrancyLock);
        reentrancyLock = true;
        _;
        reentrancyLock = false;
    }
    
    modifier onlyMeteringAuthorities {
        require(ClaimVerifier.getClaimOfType(marketAuthority, msg.sender, "", ClaimCommons.ClaimType.IsMeteringAuthority) != 0, "Invalid IsMeteringAuthority claim.");
        _;
    }
    
    modifier onlyGenerationPlants(address _plant, uint64 _balancePeriod) {
        string memory realWorldPlantId = ClaimVerifier.getRealWorldPlantId(marketAuthority, _plant);
        
        require(ClaimVerifier.getClaimOfType(marketAuthority, _plant, realWorldPlantId, ClaimCommons.ClaimType.BalanceClaim, _balancePeriod) != 0, "Invalid  BalanceClaim.");
        require(ClaimVerifier.getClaimOfTypeWithMatchingField(marketAuthority, _plant, realWorldPlantId, ClaimCommons.ClaimType.ExistenceClaim, "type", "generation", _balancePeriod) != 0, "Invalid  ExistenceClaim.");
        require(ClaimVerifier.getClaimOfType(marketAuthority, _plant, realWorldPlantId, ClaimCommons.ClaimType.MaxPowerGenerationClaim, _balancePeriod) != 0, "Invalid  MaxPowerGenerationClaim.");
        require(ClaimVerifier.getClaimOfType(marketAuthority, _plant, realWorldPlantId, ClaimCommons.ClaimType.MeteringClaim, _balancePeriod) != 0, "Invalid  MeteringClaim.");
        
        _;
    }

    constructor(IdentityContract _marketAuthority) {
        marketAuthority = _marketAuthority;
    }
    
    // IERC165 interface signature = '0x01ffc9a7'
    // IERC1155 interface signature = '0xd9b67a26'
    // IEnergyToken interface signature = '0x32d9bb6a'
    function supportsInterface(bytes4 interfaceID) override(IERC165, ERC1155) external view returns (bool) {
        return
            interfaceID == IERC165.supportsInterface.selector ||
            interfaceID == ERC1155.safeTransferFrom.selector ^ ERC1155.safeBatchTransferFrom.selector ^ ERC1155.balanceOf.selector ^ ERC1155.balanceOfBatch.selector ^ ERC1155.setApprovalForAll.selector ^ ERC1155.isApprovedForAll.selector ||
            interfaceID == IEnergyToken.decimals.selector ^ IEnergyToken.mint.selector ^ IEnergyToken.createForwards.selector ^ IEnergyToken.addMeasuredEnergyConsumption.selector ^ IEnergyToken.addMeasuredEnergyGeneration.selector ^ IEnergyToken.safeTransferFrom.selector ^ IEnergyToken.safeBatchTransferFrom.selector ^ IEnergyToken.getTokenId.selector ^ IEnergyToken.getTokenIdConstituents.selector ^ IEnergyToken.tokenKind2Number.selector ^ IEnergyToken.number2TokenKind.selector;
    }
    
    function decimals() external override(IEnergyToken) pure returns (uint8) {
        return 18;
    }
    
    function mint(uint256 _id, address[] calldata _to, uint256[] calldata _quantities) external override(IEnergyToken) noReentrancy {
        address payable generationPlantP;
        string memory realWorldPlantId;
        { // Block for avoiding stack too deep error.
        // Token needs to be mintable.
        (TokenKind tokenKind, uint64 balancePeriod, address generationPlant) = EnergyTokenLib.getTokenIdConstituents(_id);
        generationPlantP = address(uint160(generationPlant));
        require(tokenKind == TokenKind.AbsoluteForward || tokenKind == TokenKind.ConsumptionBasedForward, "tokenKind cannot be minted.");
        
        // msg.sender needs to be allowed to mint.
        require(msg.sender == generationPlant, "msg.sender needs to be allowed to mint.");
        
        // Forwards can only be minted prior to their balance period.
        require(balancePeriod > Commons.getBalancePeriod(marketAuthority.balancePeriodLength(), block.timestamp), "Wrong balance period.");
        
        // Forwards must have been created.
        require(id2Distributor[_id] != Distributor(0), "Forwards not created.");
        
        
        realWorldPlantId = ClaimVerifier.getRealWorldPlantId(marketAuthority, generationPlantP);
        require(ClaimVerifier.getClaimOfTypeWithMatchingField(marketAuthority, generationPlant, realWorldPlantId, ClaimCommons.ClaimType.ExistenceClaim, "type", "generation", Commons.getBalancePeriod(marketAuthority.balancePeriodLength(), block.timestamp)) != 0, "Invalid  ExistenceClaim.");
        require(ClaimVerifier.getClaimOfType(marketAuthority, generationPlant, realWorldPlantId, ClaimCommons.ClaimType.MaxPowerGenerationClaim) != 0, "Invalid  MaxPowerGenerationClaim.");
        EnergyTokenLib.checkClaimsForTransferSending(marketAuthority, id2Distributor, generationPlantP, realWorldPlantId, _id);
        }

        for (uint256 i = 0; i < _to.length; ++i) {
            address to = _to[i];
            uint256 quantity = _quantities[i];

            require(to != address(0x0), "_to must be non-zero.");

            if(to != msg.sender) {
                EnergyTokenLib.checkClaimsForTransferReception(marketAuthority, id2Distributor, address(uint160(to)), ClaimVerifier.getRealWorldPlantId(marketAuthority, to), _id);
            }

            // Grant the items to the caller.
            mint(to, _id, quantity);
            // In the case of absolute forwards, require that the increased supply is not above the plant's capability.
            require(supply[_id] * (1000 * 3600) <= EnergyTokenLib.getPlantGenerationCapability(marketAuthority, generationPlantP, realWorldPlantId) * marketAuthority.balancePeriodLength() * 10**18, "Plant's capability exceeded.");

            // Emit the Transfer/Mint event.
            // the 0x0 source address implies a mint
            // It will also provide the circulating supply info.
            emit TransferSingle(msg.sender, address(0x0), to, _id, quantity);

            if(to != msg.sender) {
                _doSafeTransferAcceptanceCheck(msg.sender, msg.sender, to, _id, quantity, '');
            }
            
            { // Block for avoiding stack too deep error.
            (TokenKind tokenKind, uint64 balancePeriod, address generationPlant) = EnergyTokenLib.getTokenIdConstituents(_id);
            if(tokenKind == TokenKind.ConsumptionBasedForward)
                addPlantRelationship(generationPlant, _to[i], balancePeriod);
            }
        }
    }
    
    // A reentrancy lock is not needed for this function because it does not call a different contract.
    // The recipient always is msg.sender. Therefore, _doSafeTransferAcceptanceCheck() is not called.
    function createForwards(uint64 _balancePeriod, TokenKind _tokenKind, Distributor _distributor) external override(IEnergyToken) onlyGenerationPlants(msg.sender, _balancePeriod) {
        require(_tokenKind != TokenKind.Certificate, "_tokenKind cannot be Certificate.");
        require(_balancePeriod > Commons.getBalancePeriod(marketAuthority.balancePeriodLength(), block.timestamp));
        uint256 id = EnergyTokenLib.getTokenId(_tokenKind, _balancePeriod, msg.sender);
        
        EnergyTokenLib.setId2Distributor(id2Distributor, id, _distributor);
        EnergyTokenLib.setForwardKindOfGenerationPlant(forwardKindOfGenerationPlant, _balancePeriod, msg.sender, _tokenKind);
        
        emit ForwardsCreated(_tokenKind, _balancePeriod, _distributor, id);
        
        if(_tokenKind == TokenKind.GenerationBasedForward) {
            require(!createdGenerationBasedForwards[id], "Forwards already been created.");
            createdGenerationBasedForwards[id] = true;
            
            uint256 value = 100E18;
            mint(msg.sender, id, value);
            emit TransferSingle(msg.sender, address(0x0), msg.sender, id, value);
        }
    }

    function addMeasuredEnergyConsumption(address _plant, uint256 _value, uint64 _balancePeriod) external override(IEnergyToken) onlyMeteringAuthorities {
        bool corrected = false;
        // Recognize corrected energy documentations.
        if(energyDocumentations[_plant][_balancePeriod].entered) {
            corrected = true;
        } else {
        address[] storage affectedGenerationPlants = relevantGenerationPlantsForConsumptionPlant[_balancePeriod][_plant];
            for(uint32 i = 0; i < affectedGenerationPlants.length; i++) {
                energyConsumedRelevantForGenerationPlant[_balancePeriod][affectedGenerationPlants[i]] = energyConsumedRelevantForGenerationPlant[_balancePeriod][affectedGenerationPlants[i]].add(_value);
                numberOfRelevantConsumptionPlantsUnmeasuredForGenerationPlant[_balancePeriod][affectedGenerationPlants[i]] = numberOfRelevantConsumptionPlantsUnmeasuredForGenerationPlant[_balancePeriod][affectedGenerationPlants[i]].sub(1);
            }
        }

        addMeasuredEnergyConsumption_capabilityCheck(_plant, _value);

        energyDocumentations[_plant][_balancePeriod] = EnergyTokenLib.EnergyDocumentation(IdentityContract(msg.sender), _value, corrected, false, true);
        emit EnergyDocumented(PlantType.Consumption, _value, _plant, corrected, _balancePeriod, msg.sender);
    }
    
    function addMeasuredEnergyGeneration(address _plant, uint256 _value, uint64 _balancePeriod) external override(IEnergyToken) onlyMeteringAuthorities onlyGenerationPlants(_plant, Commons.getBalancePeriod(marketAuthority.balancePeriodLength(), block.timestamp)) noReentrancy {
        bool corrected = false;
        // Recognize corrected energy documentations.
        if(energyDocumentations[_plant][_balancePeriod].entered) {
            corrected = true;
        }
        
        // Don't allow documentation of a reading above capability.
        addMeasuredEnergyGeneration_capabilityCheck(_plant, _value);

        EnergyTokenLib.EnergyDocumentation memory energyDocumentation = EnergyTokenLib.EnergyDocumentation(IdentityContract(msg.sender), _value, corrected, true, true);
        energyDocumentations[_plant][_balancePeriod] = energyDocumentation;
        
        // Mint certificates unless correcting.
        if(!corrected) {
            EnergyTokenLib.ForwardKindOfGenerationPlant memory forwardKind = forwardKindOfGenerationPlant[_balancePeriod][_plant];
            uint256 certificateId = EnergyTokenLib.getTokenId(TokenKind.Certificate, _balancePeriod, _plant);

			// If the forwards were not created, send the certificates to the generation plant. Otherwise, send them to the distributor of the forwards.
			address certificateReceiver;
			if(!forwardKind.set) {
				certificateReceiver = _plant;
			} else {
				uint256 forwardId = EnergyTokenLib.getTokenId(forwardKind.forwardKind, _balancePeriod, _plant);
				Distributor distributor = id2Distributor[forwardId];
				certificateReceiver = address(distributor);
			}

            mint(certificateReceiver, certificateId, _value);
            // Emit the Transfer/Mint event.
            // the 0x0 source address implies a mint
            // It will also provide the circulating supply info.
            emit TransferSingle(msg.sender, address(0x0), certificateReceiver, certificateId, _value);
            _doSafeTransferAcceptanceCheck(msg.sender, msg.sender, certificateReceiver, certificateId, _value, '');
        }
        emit EnergyDocumented(PlantType.Generation, _value, _plant, corrected, _balancePeriod, msg.sender);        
    }

    function addMeasuredEnergyGeneration_capabilityCheck(address _plant, uint256 _value) internal view {
        // [maxGen] = W
        // [_value] = kWh / 1e18 = 1000 * 3600 / 1e18 * W * s
        // [balancePeriodLength] = s
        
        string memory realWorldPlantId = ClaimVerifier.getRealWorldPlantId(marketAuthority, _plant);
        uint256 maxGen = EnergyTokenLib.getPlantGenerationCapability(marketAuthority, _plant, realWorldPlantId);
        require(_value * 1000 * 3600 <= maxGen * marketAuthority.balancePeriodLength() * 10**18, "Plant's capability exceeded.");
    }

    function addMeasuredEnergyConsumption_capabilityCheck(address _plant, uint256 _value) internal view {
        // [maxCon] = W
        // [_value] = kWh / 1e18 = 1000 * 3600 / 1e18 * W * s
        // [balancePeriodLength] = s
        
        string memory realWorldPlantId = ClaimVerifier.getRealWorldPlantId(marketAuthority, _plant); 
        uint256 maxCon = EnergyTokenLib.getPlantConsumptionCapability(marketAuthority, _plant, realWorldPlantId);
        // Only check if max consumption capability is known
        if (maxCon != 0)
            require(_value * 1000 * 3600 <= maxCon * marketAuthority.balancePeriodLength() * 10**18, "Plant's capability exceeded.");
    }        
    
    // ########################
    // # Overridden ERC-1155 functions
    // ########################
    function safeTransferFrom(address _from, address _to, uint256 _id, uint256 _value, bytes calldata _data) override(ERC1155, IEnergyToken) external noReentrancy {
        (TokenKind tokenKind, uint64 balancePeriod, address generationPlant) = EnergyTokenLib.getTokenIdConstituents(_id);
         if(tokenKind != TokenKind.Certificate)
            require(balancePeriod > Commons.getBalancePeriod(marketAuthority.balancePeriodLength(), block.timestamp), "balancePeriod must be in the future.");
        
        if(tokenKind == TokenKind.ConsumptionBasedForward)
            addPlantRelationship(generationPlant, _to, balancePeriod);
        
        checkClaimsForTransferAllIncluded(_from, _to, _id);
        
        // ########################
        // ERC1155.safeTransferFrom(_from, _to, _id, _value, _data);
        // ########################
        require(_to != address(0x0), "_to must be non-zero.");
        require(_from == msg.sender || operatorApproval[_from][msg.sender] == true, "Need operator approval.");

        // SafeMath will throw with insuficient funds _from
        // or if _id is not valid (balance will be 0)
        balances[_id][_from] = balances[_id][_from].sub(_value);
        balances[_id][_to]   = _value.add(balances[_id][_to]);

        // MUST emit event
        emit TransferSingle(msg.sender, _from, _to, _id, _value);

        // Now that the balance is updated and the event was emitted,
        // call onERC1155Received if the destination is a contract.
        if (_to.isContract()) {
            _doSafeTransferAcceptanceCheck(msg.sender, _from, _to, _id, _value, _data);
        }
    }
    
    function safeBatchTransferFrom(address _from, address _to, uint256[] calldata _ids, uint256[] calldata _values, bytes calldata _data) override(ERC1155, IEnergyToken) external noReentrancy {
        uint64 currentBalancePeriod = Commons.getBalancePeriod(marketAuthority.balancePeriodLength(), block.timestamp);
        
        for (uint256 i = 0; i < _ids.length; ++i) {
            (TokenKind tokenKind, uint64 balancePeriod, address generationPlant) = EnergyTokenLib.getTokenIdConstituents(_ids[i]);
            if(tokenKind != TokenKind.Certificate) {
                require(balancePeriod > currentBalancePeriod, "balancePeriod must be in the future.");
            }
            
            if(tokenKind == TokenKind.ConsumptionBasedForward)
                addPlantRelationship(generationPlant, _to, balancePeriod);

            checkClaimsForTransferAllIncluded(_from, _to, _ids[i]);
        }
        
        // ########################
        // ERC1155.safeBatchTransferFrom(_from, _to, _ids, _values, _data);
        // ########################
        // MUST Throw on errors
        require(_to != address(0x0), "destination address must be non-zero.");
        require(_ids.length == _values.length, "_ids and _values array lenght must match.");
        require(_from == msg.sender || operatorApproval[_from][msg.sender] == true, "Need operator approval for 3rd party transfers.");

        for (uint256 i = 0; i < _ids.length; ++i) {
            uint256 id = _ids[i];
            uint256 value = _values[i];

            // SafeMath will throw with insuficient funds _from
            // or if _id is not valid (balance will be 0)
            balances[id][_from] = balances[id][_from].sub(value);
            balances[id][_to]   = value.add(balances[id][_to]);
        }

        // Note: instead of the below batch versions of event and acceptance check you MAY have emitted a TransferSingle
        // event and a subsequent call to _doSafeTransferAcceptanceCheck in above loop for each balance change instead.
        // Or emitted a TransferSingle event for each in the loop and then the single _doSafeBatchTransferAcceptanceCheck below.
        // However it is implemented the balance changes and events MUST match when a check (i.e. calling an external contract) is done.

        // MUST emit event
        emit TransferBatch(msg.sender, _from, _to, _ids, _values);

        // Now that the balances are updated and the events are emitted,
        // call onERC1155BatchReceived if the destination is a contract.
        if (_to.isContract()) {
            _doSafeBatchTransferAcceptanceCheck(msg.sender, _from, _to, _ids, _values, _data);
        }
    }
    
    function checkClaimsForTransferAllIncluded(address _from, address _to, uint256 _id) internal view {
        // This needs to be checked here because otherwise distributors would need real world plant IDs
        // as without them, getting the real world plant ID to pass on to checkClaimsForTransferSending
        // and checkClaimsForTransferReception would cause a revert.
        (TokenKind tokenKind, ,) = EnergyTokenLib.getTokenIdConstituents(_id);
        if(tokenKind == TokenKind.Certificate) {
            return;
        }
        
        string memory realWorldPlantIdFrom = ClaimVerifier.getRealWorldPlantId(marketAuthority, _from);
        string memory realWorldPlantIdTo = ClaimVerifier.getRealWorldPlantId(marketAuthority, _to);
        EnergyTokenLib.checkClaimsForTransferSending(marketAuthority, id2Distributor, address(uint160(_from)), realWorldPlantIdFrom, _id);
        EnergyTokenLib.checkClaimsForTransferReception(marketAuthority, id2Distributor, address(uint160(_to)), realWorldPlantIdTo, _id);
    }
    
    // ########################
    // # Public support functions
    // ########################
    function getTokenId(TokenKind _tokenKind, uint64 _balancePeriod, address _identityContractAddress) public pure override(IEnergyToken) returns (uint256 __tokenId) {
        __tokenId = EnergyTokenLib.getTokenId(_tokenKind, _balancePeriod, _identityContractAddress);
    }
    
    function getTokenIdConstituents(uint256 _tokenId) public pure override(IEnergyToken) returns(TokenKind __tokenKind, uint64 __balancePeriod, address __identityContractAddress) {
        (__tokenKind, __balancePeriod, __identityContractAddress) = EnergyTokenLib.getTokenIdConstituents(_tokenId);
    }
    
    function tokenKind2Number(TokenKind _tokenKind) public pure override(IEnergyToken) returns (uint8 __number) {
        __number = EnergyTokenLib.tokenKind2Number(_tokenKind);
    }
    
    function number2TokenKind(uint8 _number) public pure override(IEnergyToken) returns (TokenKind __tokenKind) {
        __tokenKind = EnergyTokenLib.number2TokenKind(_number);
    }
    
    // ########################
    // # Internal functions
    // ########################
    function addPlantRelationship(address _generationPlant, address _consumptionPlant, uint64 _balancePeriod) public {
        relevantGenerationPlantsForConsumptionPlant[_balancePeriod][_consumptionPlant].push(_generationPlant);
        
        if(!energyDocumentations[_consumptionPlant][_balancePeriod].generated)
            require(energyDocumentations[_consumptionPlant][_balancePeriod].value == 0, "_consumptionPlant does already have energyDocumentations for _balancePeriod.");
        
        numberOfRelevantConsumptionPlantsForGenerationPlant[_balancePeriod][_generationPlant]++; // not gonna overflow
        numberOfRelevantConsumptionPlantsUnmeasuredForGenerationPlant[_balancePeriod][_generationPlant]++; // not gonna overflow
    }
}
