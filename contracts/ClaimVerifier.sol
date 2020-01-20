pragma solidity ^0.5.0;

import "./Commons.sol";
import "./IdentityContract.sol";
import "./ClaimCommons.sol";
import "./../dependencies/jsmnSol/contracts/JsmnSolLib.sol";
import "./../dependencies/dapp-bin/library/stringUtils.sol";

library ClaimVerifier {
    function verifyFirstLevelClaim(IdentityContract marketAuthority, address payable _subject, ClaimCommons.ClaimType _firstLevelClaim) public view returns(uint256 __claimId) {
        // Make sure the given claim actually is a first-level claim.
        require(_firstLevelClaim == ClaimCommons.ClaimType.IsBalanceAuthority || _firstLevelClaim == ClaimCommons.ClaimType.IsMeteringAuthority || _firstLevelClaim == ClaimCommons.ClaimType.IsPhysicalAssetAuthority || _firstLevelClaim == ClaimCommons.ClaimType.IdentityContractFactoryClaim || _firstLevelClaim == ClaimCommons.ClaimType.EnergyTokenContractClaim || _firstLevelClaim == ClaimCommons.ClaimType.MarketRulesClaim);
        
        uint256 topic = ClaimCommons.claimType2Topic(_firstLevelClaim);
        uint256[] memory claimIds = IdentityContract(_subject).getClaimIdsByTopic(topic);
        
        for(uint64 i = 0; i < claimIds.length; i++) {
            (uint256 cTopic, uint256 cScheme, address cIssuer, bytes memory cSignature, bytes memory cData,) = IdentityContract(_subject).getClaim(claimIds[i]);
            
            if(cTopic != topic)
                continue;
                
            if(cIssuer != address(marketAuthority))
                continue;
            
            bool correct = marketAuthority.verifySignature(cTopic, cScheme, cIssuer, cSignature, cData);
            if(correct)
                return claimIds[i];
        }
        
        return 0;
    }
    
    function verifySecondLevelClaim(IdentityContract marketAuthority, address payable _subject, ClaimCommons.ClaimType _secondLevelClaim) public view returns(uint256 __claimId) {
        // Make sure the given claim actually is a second-level claim.
        require(_secondLevelClaim == ClaimCommons.ClaimType.MeteringClaim || _secondLevelClaim == ClaimCommons.ClaimType.BalanceClaim || _secondLevelClaim == ClaimCommons.ClaimType.ExistenceClaim || _secondLevelClaim == ClaimCommons.ClaimType.GenerationTypeClaim || _secondLevelClaim == ClaimCommons.ClaimType.LocationClaim || _secondLevelClaim == ClaimCommons.ClaimType.AcceptedDistributorContractsClaim);
        uint256 topic = ClaimCommons.claimType2Topic(_secondLevelClaim);
        uint256[] memory claimIds = IdentityContract(_subject).getClaimIdsByTopic(topic);
        
        for(uint64 i = 0; i < claimIds.length; i++) {
            (uint256 cTopic, uint256 cScheme, address cIssuer, bytes memory cSignature, bytes memory cData,) = IdentityContract(_subject).getClaim(claimIds[i]);
            
            if(cTopic != topic)
                continue;
                
            bool correctAccordingToSecondLevelAuthority = IdentityContract(address(uint160(cIssuer))).verifySignature(cTopic, cScheme, cIssuer, cSignature, cData);
            __claimId = verifyFirstLevelClaim(marketAuthority, address(uint160(cIssuer)), ClaimCommons.getHigherLevelClaim(_secondLevelClaim));
            if(correctAccordingToSecondLevelAuthority && __claimId != 0) {
                return __claimId;
            }
        }
        
        return 0;
    }
    
    function verifyClaim(IdentityContract marketAuthority, address payable _subject, ClaimCommons.ClaimType _claimType) public view returns(uint256 __claimId) {
        if(_claimType == ClaimCommons.ClaimType.IsBalanceAuthority || _claimType == ClaimCommons.ClaimType.IsMeteringAuthority || _claimType == ClaimCommons.ClaimType.IsPhysicalAssetAuthority || _claimType == ClaimCommons.ClaimType.IdentityContractFactoryClaim || _claimType == ClaimCommons.ClaimType.EnergyTokenContractClaim || _claimType == ClaimCommons.ClaimType.MarketRulesClaim) {
            return verifyFirstLevelClaim(marketAuthority, _subject, _claimType);
        }
        
        if(_claimType == ClaimCommons.ClaimType.MeteringClaim || _claimType == ClaimCommons.ClaimType.BalanceClaim || _claimType == ClaimCommons.ClaimType.ExistenceClaim || _claimType == ClaimCommons.ClaimType.GenerationTypeClaim || _claimType == ClaimCommons.ClaimType.LocationClaim || _claimType == ClaimCommons.ClaimType.AcceptedDistributorContractsClaim) {
            return verifySecondLevelClaim(marketAuthority, _subject, _claimType);
        }
        
        require(false);
    }
    
    /**
     * This method does not verify that the given claim exists in the contract. It merely checks whether it is a valid claim.
     * 
     * Use this method before adding claims to make sure that only valid claims are added.
     */
    function validateClaim(IdentityContract marketAuthority, ClaimCommons.ClaimType _claimType, uint256 _topic, uint256 _scheme, address _issuer, bytes memory _signature, bytes memory _data) public view returns(bool) {
        if(ClaimCommons.claimType2Topic(_claimType) != _topic)
            return false;
        
        if(_claimType == ClaimCommons.ClaimType.IsBalanceAuthority || _claimType == ClaimCommons.ClaimType.IsMeteringAuthority || _claimType == ClaimCommons.ClaimType.IsPhysicalAssetAuthority || _claimType == ClaimCommons.ClaimType.IdentityContractFactoryClaim || _claimType == ClaimCommons.ClaimType.EnergyTokenContractClaim || _claimType == ClaimCommons.ClaimType.MarketRulesClaim) {
            bool correct = marketAuthority.verifySignature(_topic, _scheme, _issuer, _signature, _data);
            return correct;
        }
        
        if(_claimType == ClaimCommons.ClaimType.MeteringClaim || _claimType == ClaimCommons.ClaimType.BalanceClaim || _claimType == ClaimCommons.ClaimType.ExistenceClaim || _claimType == ClaimCommons.ClaimType.GenerationTypeClaim || _claimType == ClaimCommons.ClaimType.LocationClaim || _claimType == ClaimCommons.ClaimType.AcceptedDistributorContractsClaim) {
            bool correctAccordingToSecondLevelAuthority = IdentityContract(address(uint160(_issuer))).verifySignature(_topic, _scheme, _issuer, _signature, _data);
            return correctAccordingToSecondLevelAuthority && (verifyFirstLevelClaim(marketAuthority, address(uint160(_issuer)), ClaimCommons.getHigherLevelClaim(_claimType)) != 0);
        }
        
        require(false);
    }
    
    /**
     * Returns the claim ID of a claim of the stated type. This method  only makes sure that the claim exists. It does not verify the claim.
     * 
     * Iff requireNonExpired is set, only claims that have not yet expired are considered.
     */
    function getClaimOfType(address payable _subject, ClaimCommons.ClaimType _claimType, bool requireNonExpired) public view returns (uint256 __claimId) {
        uint256 topic = ClaimCommons.claimType2Topic(_claimType);
        uint256[] memory claimIds = IdentityContract(_subject).getClaimIdsByTopic(topic);
        
        for(uint64 i = 0; i < claimIds.length; i++) {
            (uint256 cTopic, , , , bytes memory cData,) = IdentityContract(_subject).getClaim(claimIds[i]);
            
            if(cTopic != topic)
                continue;
                
            if(requireNonExpired && getExpiryDate(cData) > Commons.getBalancePeriod())
                continue;
            
            return claimIds[i];
        }
        
        return 0;
    }
    
    function getClaimOfTypeWithMatchingField(address payable _subject, ClaimCommons.ClaimType _claimType, string memory _fieldName, string memory _fieldContent, bool requireNonExpired) public view returns (uint256 __claimId) {
        uint256 topic = ClaimCommons.claimType2Topic(_claimType);
        uint256[] memory claimIds = IdentityContract(_subject).getClaimIdsByTopic(topic);
        
        for(uint64 i = 0; i < claimIds.length; i++) {
            (uint256 cTopic, , , , bytes memory cData,) = IdentityContract(_subject).getClaim(claimIds[i]);
            
            if(cTopic != topic)
                continue;
            
            if(requireNonExpired && getExpiryDate(cData) > Commons.getBalancePeriod())
                continue;
            
            // Separate function call to avoid stack too deep error.
            if(doesMatchingFieldExist(_fieldName, _fieldContent, cData)) {
                return claimIds[i];
            }
        }
        
        return 0;
    }
    
    function doesMatchingFieldExist(string memory _fieldName, string memory _fieldContent, bytes memory data) internal pure returns(bool) {
        string memory json = string(data);
        (uint exitCode, JsmnSolLib.Token[] memory tokens, uint numberOfTokensFound) = JsmnSolLib.parse(json, 5);
        assert(exitCode == 0);
        
        for(uint i = 1; i <= numberOfTokensFound; i += 2) { // TODO: check value of numberOfTokensFound. Maybe subtract something here.
            JsmnSolLib.Token memory keyToken = tokens[i];
            JsmnSolLib.Token memory valueToken = tokens[i+1];

            if(StringUtils.equal(JsmnSolLib.getBytes(json, keyToken.start, keyToken.end), _fieldName) && StringUtils.equal(JsmnSolLib.getBytes(json, valueToken.start, valueToken.end), _fieldContent)) {
                return true;
            }
        }
        return false;
    }
    
    function getUint64Field(string memory fieldName, bytes memory data) public pure returns(uint64) {
        int expiryDateAsInt = JsmnSolLib.parseInt(getStringField(fieldName, data));
        require(expiryDateAsInt >= 0);
        require(expiryDateAsInt < 0x10000000000000000);
        return uint64(expiryDateAsInt);
    }
    
    function getStringField(string memory fieldName, bytes memory data) public pure returns(string memory) {
        string memory json = string(data);
        (uint exitCode, JsmnSolLib.Token[] memory tokens, uint numberOfTokensFound) = JsmnSolLib.parse(json, 5); // TODO: Check whether this works as there is a comment on SE saying it doesn't: https://ethereum.stackexchange.com/questions/2519/how-to-convert-a-bytes32-to-string#comment78462_59335
        assert(exitCode == 0);
        
        for(uint i = 1; i <= numberOfTokensFound; i += 2) { // TODO: check value of numberOfTokensFound. Maybe subtract something here.
            JsmnSolLib.Token memory keyToken = tokens[i];
            JsmnSolLib.Token memory valueToken = tokens[i+1];
            
            if(StringUtils.equal(JsmnSolLib.getBytes(json, keyToken.start, keyToken.end), fieldName)) {
                return JsmnSolLib.getBytes(json, valueToken.start, valueToken.end);
            }
        }
        
        require(false);
    }
    
    function getExpiryDate(bytes memory data) public pure returns(uint64) {
        return getUint64Field("expiryDate", data);
    }
}
