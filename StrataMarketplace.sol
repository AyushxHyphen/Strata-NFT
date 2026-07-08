// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * STRATA — Lineage-Native NFT Exchange
 * ---------------------------------------------------------------
 * Reference sketch of the on-chain logic behind the demo. This is
 * intentionally minimal (no gas-golfing, no upgradeability) so the
 * mechanics stay readable. Three ideas that differ from a standard
 * ERC-721 marketplace:
 *
 * 1. LINEAGE ROYALTY CASCADE
 *    Standard marketplaces pay a single royalty % to the original
 *    creator on every resale. Here, every past owner is a
 *    stakeholder: 10% of each sale is split across the full
 *    ownership chain, weighted 0.5^n by recency, so early flippers
 *    who held quality pieces keep earning as the piece keeps moving.
 *
 * 2. FUSION (BURN-TO-MINT)
 *    Two owned tokens can be burned together to mint a new token
 *    whose provenance permanently records both parent token IDs,
 *    enabling on-chain ancestry graphs instead of flat collections.
 *
 * 3. CROWD-UNLOCK LISTINGS
 *    A token can be listed against a pooled reserve instead of a
 *    single buyer. Once the reserve is met, the token is wrapped
 *    into a fractional-ownership record split by contribution.
 * ---------------------------------------------------------------
 */
contract StrataMarketplace is ERC721, ReentrancyGuard, Ownable {
    uint256 public nextTokenId = 1;
    uint256 public constant ROYALTY_BPS = 1000; // 10% of every sale, in basis points
    uint256 public constant BPS_DENOM = 10000;

    struct LineageEntry {
        address holder;
        uint64 timestamp;
        uint128 pricePaid; // 0 for genesis / fusion mints
    }

    struct Listing {
        uint256 price;
        bool active;
    }

    struct FractionalPool {
        uint256 goal;
        uint256 raised;
        bool unlocked;
        mapping(address => uint256) contributions;
        address[] contributors;
    }

    mapping(uint256 => LineageEntry[]) public lineage;      // full ownership history per token
    mapping(uint256 => uint256[2]) public parentsOf;         // fusion ancestry, [0,0] if genesis
    mapping(uint256 => Listing) public listings;
    mapping(uint256 => FractionalPool) private pools;

    event GenesisMinted(uint256 indexed tokenId, address indexed creator);
    event Fused(uint256 indexed childId, uint256 indexed parentA, uint256 indexed parentB, address owner);
    event Listed(uint256 indexed tokenId, uint256 price);
    event Sold(uint256 indexed tokenId, address indexed from, address indexed to, uint256 price, uint256 royaltyPaid);
    event PoolContribution(uint256 indexed tokenId, address indexed contributor, uint256 amount);
    event PoolUnlocked(uint256 indexed tokenId, uint256 totalContributors);

    constructor() ERC721("Strata", "STRATA") Ownable(msg.sender) {}

    /* ---------------------------------------------------------- */
    /* GENESIS MINT                                                */
    /* ---------------------------------------------------------- */
    function mintGenesis() external returns (uint256 tokenId) {
        tokenId = nextTokenId++;
        _safeMint(msg.sender, tokenId);
        lineage[tokenId].push(LineageEntry(msg.sender, uint64(block.timestamp), 0));
        parentsOf[tokenId] = [0, 0];
        emit GenesisMinted(tokenId, msg.sender);
    }

    /* ---------------------------------------------------------- */
    /* LISTING + LINEAGE ROYALTY CASCADE SALE                      */
    /* ---------------------------------------------------------- */
    function list(uint256 tokenId, uint256 price) external {
        require(ownerOf(tokenId) == msg.sender, "not owner");
        require(price > 0, "price=0");
        listings[tokenId] = Listing(price, true);
        emit Listed(tokenId, price);
    }

    function buy(uint256 tokenId) external payable nonReentrant {
        Listing memory l = listings[tokenId];
        require(l.active, "not listed");
        require(msg.value == l.price, "wrong value");

        address seller = ownerOf(tokenId);
        LineageEntry[] storage chain = lineage[tokenId];

        uint256 royaltyPool = (l.price * ROYALTY_BPS) / BPS_DENOM;
        uint256 sellerProceeds = l.price - royaltyPool;

        // build the list of distinct prior holders, excluding the current seller
        uint256 priorCount;
        for (uint256 i = 0; i < chain.length; i++) {
            if (chain[i].holder != seller) priorCount++;
        }

        if (priorCount == 0) {
            // genesis sale — no cascade, seller/creator keeps it all
            sellerProceeds = l.price;
            royaltyPool = 0;
        } else {
            // weight = 0.5^stepsFromMostRecent, computed in fixed-point (1e18)
            uint256[] memory weights = new uint256[](priorCount);
            uint256 wSum;
            uint256 idx;
            for (uint256 i = chain.length; i > 0; i--) {
                LineageEntry memory entry = chain[i - 1];
                if (entry.holder == seller) continue;
                uint256 w = 1e18 >> idx; // halves each step further back
                weights[idx] = w;
                wSum += w;
                idx++;
                if (idx == priorCount) break;
            }
            idx = 0;
            for (uint256 i = chain.length; i > 0; i--) {
                LineageEntry memory entry = chain[i - 1];
                if (entry.holder == seller) continue;
                uint256 share = (royaltyPool * weights[idx]) / wSum;
                if (share > 0) {
                    (bool ok, ) = entry.holder.call{value: share}("");
                    require(ok, "royalty transfer failed");
                }
                idx++;
                if (idx == priorCount) break;
            }
        }

        (bool sok, ) = seller.call{value: sellerProceeds}("");
        require(sok, "seller transfer failed");

        _transfer(seller, msg.sender, tokenId);
        chain.push(LineageEntry(msg.sender, uint64(block.timestamp), uint128(l.price)));
        listings[tokenId].active = false;

        emit Sold(tokenId, seller, msg.sender, l.price, royaltyPool);
    }

    /* ---------------------------------------------------------- */
    /* FUSION — burn two tokens, mint a hybrid with dual ancestry   */
    /* ---------------------------------------------------------- */
    function fuse(uint256 tokenIdA, uint256 tokenIdB) external returns (uint256 childId) {
        require(ownerOf(tokenIdA) == msg.sender && ownerOf(tokenIdB) == msg.sender, "not owner of both");
        require(tokenIdA != tokenIdB, "same token");

        _burn(tokenIdA);
        _burn(tokenIdB);
        listings[tokenIdA].active = false;
        listings[tokenIdB].active = false;

        childId = nextTokenId++;
        _safeMint(msg.sender, childId);
        lineage[childId].push(LineageEntry(msg.sender, uint64(block.timestamp), 0));
        parentsOf[childId] = [tokenIdA, tokenIdB];

        emit Fused(childId, tokenIdA, tokenIdB, msg.sender);
    }

    /* ---------------------------------------------------------- */
    /* CROWD-UNLOCK LISTING                                        */
    /* ---------------------------------------------------------- */
    function openPool(uint256 tokenId, uint256 goal) external {
        require(ownerOf(tokenId) == msg.sender, "not owner");
        FractionalPool storage p = pools[tokenId];
        require(p.goal == 0, "pool exists");
        p.goal = goal;
    }

    function contribute(uint256 tokenId) external payable nonReentrant {
        FractionalPool storage p = pools[tokenId];
        require(p.goal > 0, "no pool");
        require(!p.unlocked, "already unlocked");

        if (p.contributions[msg.sender] == 0) p.contributors.push(msg.sender);
        p.contributions[msg.sender] += msg.value;
        p.raised += msg.value;
        emit PoolContribution(tokenId, msg.sender, msg.value);

        if (p.raised >= p.goal) {
            p.unlocked = true;
            // token custody moves to this contract; off-chain / L2 registry
            // tracks each contributor's fractional bps for future proceeds
            // splits (full ERC-1155 wrapping omitted here for brevity).
            _transfer(ownerOf(tokenId), address(this), tokenId);
            emit PoolUnlocked(tokenId, p.contributors.length);
        }
    }

    function contributorsOf(uint256 tokenId) external view returns (address[] memory) {
        return pools[tokenId].contributors;
    }
}
