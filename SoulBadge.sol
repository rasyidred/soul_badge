// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

// must use specific version of ERC721 standard
import "@openzeppelin/contracts@4.7.0/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts@4.7.0/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts@4.7.0/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title SoulBagde
 * Gimana cara transfer NFTnya nanti dengan kode referral
 */

contract SoulBadge is ERC721, ERC721URIStorage, ERC721Burnable, ReentrancyGuard  {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdCounter;

    address public contractOwner;

    modifier checkValid(bytes32 secretCode){
        require(eventDetails[secretCode].isExist == true, "The code is not valid nor exist");
        _;
    }

    constructor() ERC721("SoulBadge", "SBT"){
        contractOwner = msg.sender;
    }

    event EventCreated (uint maxAttendees, string eventInfo, bytes32 secretCode);
    event BadgeDistributed (address recipient, bytes32 secretCode, uint tokenId, string tokenURI);
    event Attest (address indexed to, uint indexed tokenId);
    event Revoke (address indexed to, uint indexed tokenId);

    struct registeredEvent{
        bytes32 secretCode;
        uint tokenId;
    }

    struct eventList{
        uint counter;
        mapping (uint => registeredEvent) badgeInfo;
    }
    
    struct Claimer{
        address attendee;
        uint tokenId;
        bool claimed;
    }

    struct Details{
        uint maxAttendees;
        uint counterClaimed;
        uint startingTokenId;
        uint endingTokenId;
        string URI;
        bool isExist;
        mapping (address => Claimer) attendeeDetails;
        Claimer[] claimers;
    }

    mapping (bytes32 => Details) public eventDetails; //input: secretCode
    mapping (address => eventList) public userBadge; //record all badges that user has
    // mapping (address => userBadge) public userBadges;
    
    // function _baseURI() internal pure override returns(string memory) {
    //     return "<https://www.myapp.com/>";
    // }
    

    function createEvent(uint _noOfAttendees, string memory _tokenURI) public nonReentrant returns (bytes32 secretCode){
        secretCode = keccak256(abi.encodePacked(block.timestamp, _noOfAttendees, _tokenURI));
        uint startingTokenId;
        if (_tokenIdCounter.current() == 0){
            startingTokenId = 1;
        } else{
            startingTokenId = _tokenIdCounter.current();
        }

        uint endingTokenId = startingTokenId + _noOfAttendees;

        eventDetails[secretCode].maxAttendees = _noOfAttendees;
        eventDetails[secretCode].startingTokenId = startingTokenId;
        eventDetails[secretCode].endingTokenId = endingTokenId;
        eventDetails[secretCode].URI = _tokenURI;
        eventDetails[secretCode].isExist = true;
       
        for (uint i=0; i < _noOfAttendees; i++){
            _tokenIdCounter.increment();
            uint tokenId = _tokenIdCounter.current();
            
            _safeMint(contractOwner, tokenId);
            _setTokenURI(tokenId, _tokenURI);
            // setApprovalForAll(storageAddress, true); 
        }
        emit EventCreated(_noOfAttendees, _tokenURI, secretCode);

        return secretCode;
    }

    function distributeBadges(bytes32 _secretCode, address _to) public checkValid(_secretCode) nonReentrant returns (uint tokenId) {
        bool isClaimed = eventDetails[_secretCode].attendeeDetails[_to].claimed;
        require(isClaimed == false, "Recipient already claimed the Token");

        //require max claim
        uint remainingTokens = getRemainingTokens(_secretCode);
        require(remainingTokens > 0, "The maximum claims reached!");
        
        //record all attendees' details who are already claimed to Details struct
        //biar memudahkan saat ngambil semua data attendee-nya
        tokenId = getTokenId(_secretCode);
        eventDetails[_secretCode].claimers.push(Claimer(_to, tokenId, true)); 

        //record each attendee that is already claimed, to prevent double spending/minting to the same address
        eventDetails[_secretCode].attendeeDetails[_to] = Claimer(_to, tokenId, true);

        // transfer ownership dari minter (contractOwner) ke attendee
        safeTransferFrom(contractOwner, _to, tokenId);

        eventDetails[_secretCode].counterClaimed += 1;

        //Record user's badge
        uint badgeCounter = userBadge[_to].counter;
        userBadge[_to].badgeInfo[badgeCounter].secretCode = _secretCode;
        userBadge[_to].badgeInfo[badgeCounter].tokenId = tokenId;
        userBadge[_to].counter +=1 ;

        emit BadgeDistributed(_to, _secretCode ,tokenId, eventDetails[_secretCode].URI);

        return tokenId;
    }

    /* Getter Functions */
    function getUserBadge (address _address, uint idx) public view returns (bytes32 secretCode, uint tokenId){
        secretCode = userBadge[_address].badgeInfo[idx].secretCode;
        tokenId = userBadge[_address].badgeInfo[idx].tokenId;
    }

    function getRemainingTokens(bytes32 secretCode) internal view returns (uint remainingTokens) {
        uint startingTokenId = eventDetails[secretCode].startingTokenId;
        uint endingTokenId   = eventDetails[secretCode].endingTokenId;
        uint claimed = eventDetails[secretCode].counterClaimed;
        remainingTokens = endingTokenId - startingTokenId - claimed;
    }

    function getTokenId(bytes32 secretCode) internal view returns (uint tokenId){
        tokenId = eventDetails[secretCode].counterClaimed + eventDetails[secretCode].startingTokenId;
    }

    function getAttendees(bytes32 secretCode) public view returns (address[] memory addresses, uint[] memory tokenIds, bool[] memory claimed){
        
        addresses = new address[](eventDetails[secretCode].maxAttendees);
        tokenIds  = new uint[](eventDetails[secretCode].maxAttendees);
        claimed   = new bool[](eventDetails[secretCode].maxAttendees);

        for(uint i; i<eventDetails[secretCode].maxAttendees; i++){
            addresses[i]    = eventDetails[secretCode].claimers[i].attendee;
            tokenIds[i]     = eventDetails[secretCode].claimers[i].tokenId;
            claimed[i]      = eventDetails[secretCode].claimers[i].claimed;
        }
        return (addresses, tokenIds, claimed);
    }


    /* The following functions are overrides required by Solidity. */
    // function _afterTokenTransfer(address from, address to, uint256 tokenId)
    // internal override(ERC721) {
    //     super._afterTokenTransfer(from, to, tokenId);
    // }

    // function _beforeTokenTransfer(address from, address to, uint256 tokenId)
    // internal override(ERC721) {
    //     require(from == address(0) || to == address(0) ||
    //             from == contractOwner, "Err: token is not transferable");
    //     super._beforeTokenTransfer(from, to, tokenId);
    // }

    function _beforeTokenTransfer(address from, address to, uint256) pure internal override {
        require(from == address(0) || to == address(0), "Not allowed to transfer token");
    }

    function _afterTokenTransfer(address from, address to, uint256 tokenId) override internal {

        if (from == address(0)) {
            emit Attest(to, tokenId);
        } else if (to == address(0)) {
            emit Revoke(to, tokenId);
        }
    }

    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) 
    returns (string memory){
        return super.tokenURI(tokenId);
    }

}
