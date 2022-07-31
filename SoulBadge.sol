// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title SoulBagde
 * Non-tranferrable digital badge using Soulbound Token
 */

contract SoulBadge is ERC721URIStorage, Ownable, ReentrancyGuard, ERC721Burnable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdCounter;

    address public contractOwner;
    address public storageAddress;

    modifier checkValid(bytes32 secretCode){
        require(eventDetails[secretCode].isExist == true, "The code is not valid nor exist");
        _;
    }

    constructor(address _storageAddress) ERC721("SoulBadge", "SBT"){
        contractOwner = msg.sender;
        storageAddress = _storageAddress;
    }

    event eventCreated (uint maxAttendees, string eventInfo, bytes32 secretCode);
    

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

    // function _baseURI() internal pure override returns(string memory) {
    //     return "<https://www.myapp.com/>";
    // }
    

    function mintNFTs(uint _noOfAttendees, string memory _tokenURI) public onlyOwner nonReentrant returns (bytes32 secretCode){
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
            setApprovalForAll(storageAddress, true);
        }
        emit eventCreated(_noOfAttendees, _tokenURI, secretCode);
    }

    function claim(bytes32 _secretCode, address _to) public checkValid(_secretCode) nonReentrant returns (uint tokenId, uint remainingTokens) {
        bool isClaimed = eventDetails[_secretCode].attendeeDetails[_to].claimed;
        require(isClaimed == false, "Recipient already claimed the Token");

        //require max claim
        remainingTokens = getRemainingTokens(_secretCode);
        require(remainingTokens > 0, "The maximum claims reached!");
        
        //record all attendees' details who are already claimed to Details struct
        //biar memudahkan saat ngambil semua data attendee-nya
        tokenId = getTokenId(_secretCode);
        eventDetails[_secretCode].claimers.push(Claimer(_to, tokenId, true)); 

        //record each attendee that is already claimed, to prevent double spending/minting to the same address
        eventDetails[_secretCode].attendeeDetails[_to] = Claimer(_to, tokenId, true);

        // transfer ownership dari minter (contractOwner) ke attendee => move to BadgeStorage
        // safeTransferFrom(contractOwner, _to, tokenId);

        eventDetails[_secretCode].counterClaimed += 1;
        return (tokenId, remainingTokens);
    }

    /* Getter Functions */
    function getRemainingTokens(bytes32 secretCode) internal view returns (uint remainingTokens) {
        uint startingTokenId = eventDetails[secretCode].startingTokenId;
        uint endingTokenId   = eventDetails[secretCode].endingTokenId;
        uint claimed = eventDetails[secretCode].counterClaimed;
        remainingTokens = endingTokenId - startingTokenId - claimed;
    }

    function getTokenId(bytes32 secretCode) internal view returns (uint tokenId){
        tokenId = eventDetails[secretCode].counterClaimed + eventDetails[secretCode].startingTokenId;
    }

    function getClaimer(bytes32 secretCode) public view returns (address[] memory addresses, uint[] memory tokenIds, bool[] memory claimed){
        
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
    function _afterTokenTransfer(address from, address to, uint256 tokenId)
    internal override(ERC721) {
        super._afterTokenTransfer(from, to, tokenId);
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
    internal override(ERC721) {
        // gak bisa ditransfer kalau udah dikasih dari address contract ini
        require(from == address(0) || to == address(0) ||
                from == storageAddress || to == storageAddress, "Err: token is SOUL BOUND");
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) 
    returns (string memory){
        return super.tokenURI(tokenId);
    }

}

/* SOULBADGE STORAGE TO MAKE CLAIM EASIER */

contract BadgeStorage is ReentrancyGuard, Ownable{
    using Counters for Counters.Counter;

    Counters.Counter private itemIds;
    Counters.Counter private itemsRedeemed;

    struct StorageItem{
        address nftContract;
        uint tokenId;
        address creator; //NFT creator
        address owner; //owner after it's being transfered
        bool claim;
    }

    mapping(uint => StorageItem) private idToStorageItem;

    event ItemStored(address indexed nftContract,
                     uint indexed tokenId,
                     address creator,
                     address owner,
                     bool claim);

    event badgeClaimed (address recipient, uint tokenId, uint remainingTokens);

    /* Stores an NFT on the storage before distributed */ 
    // create market item
    function storeItem(address nftContract, uint tokenId) public payable nonReentrant onlyOwner{
        require(idToStorageItem[tokenId].claim == false, "You can't store a redeemed token!");
              
        idToStorageItem[tokenId] = StorageItem(nftContract, tokenId, payable(msg.sender), payable(address(0)), false); 
        IERC721(nftContract).transferFrom(msg.sender, address(this), tokenId);

        emit ItemStored(nftContract, tokenId, msg.sender, address(0), false);
    }                

    /* Transfers the NFT's ownership to attendee (msg.sender)*/
    // buy nft
    function claimBadge(address nftContract, bytes32 secretCode) public nonReentrant{
        SoulBadge _SoulBadge = SoulBadge(nftContract); 

        require(msg.sender != owner(), "Only attendees that can claim!");
        (uint tokenId, uint remainingTokens) = _SoulBadge.claim(secretCode, msg.sender);

        idToStorageItem[tokenId].owner = (msg.sender);
        idToStorageItem[tokenId].claim = true;

        IERC721(_SoulBadge).transferFrom(address(this), msg.sender, tokenId);

        emit badgeClaimed (msg.sender, tokenId, remainingTokens);
    }
    
    /*Returns all NFTs which has not been claimed*/


    // /*Returns all NFTs which has been redeemed*/
    
}
