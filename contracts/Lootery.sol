// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import {FeistelShuffleOptimised} from "./lib/FeistelShuffleOptimised.sol";
import {Sort} from "./lib/Sort.sol";
import {ERC721, ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IRandomiserCallback} from "./interfaces/IRandomiserCallback.sol";
import {IRandomiserGen2} from "./interfaces/IRandomiserGen2.sol";

/// @title Lootery
/// @notice Lotto the ultimate
contract Lootery is IRandomiserCallback, ERC721Enumerable, Ownable {
    using Sort for uint8[];

    /// @notice Current state of the lootery
    enum GameState {
        /// @notice This is the only state where the jackpot can increase
        Purchase,
        /// @notice Waiting for VRF fulfilment
        DrawPending
    }

    /// @notice A ticket to be purchased
    struct Ticket {
        /// @notice For whomst shall this purchase be made out
        address whomst;
        /// @notice Lotto numbers, pick wisely! Picks must be ASCENDINGLY
        ///     ORDERED, with NO DUPLICATES!
        uint8[] picks;
    }

    /// @notice Describes an inflight randomness request
    struct RandomnessRequest {
        uint208 requestId;
        uint48 timestamp;
    }

    /// @notice How many numbers must be picked per draw (and per ticket)
    ///     The range of this number should be something like 3-7
    uint256 public immutable numPicks;
    /// @notice Maximum value of a ball (pick) s.t. value \in [1, maxBallValue]
    uint8 public immutable maxBallValue;
    /// @notice How long a game lasts in seconds (before numbers are drawn)
    uint256 public immutable gamePeriod;
    /// @notice Trusted randomiser
    address public immutable randomiser;
    /// @notice Ticket price
    uint256 public immutable ticketPrice;
    /// @notice Percentage of ticket price directed to the community
    uint256 public immutable communityFeeBps;

    /// @dev Current token id
    uint256 private currentTokenId;
    /// @notice State of the game
    GameState public gameState;
    /// @notice Monotonically increasing game id
    uint256 public currentGameId;
    /// @notice Current random request details
    RandomnessRequest public randomnessRequest;
    /// @notice Winning pick identities per game, once they've been drawn
    mapping(uint256 gameId => uint256) public winningPickIds;
    /// @notice token id => picks
    mapping(uint256 tokenId => uint8[]) public tokenIdToTicket;
    /// @notice token id => game id
    mapping(uint256 tokenId => uint256) public tokenIdToGameId;
    /// @notice Game id => pick identity => tokenIds
    mapping(uint256 gameId => mapping(uint256 id => uint256[]))
        public tokenByPickIdentity;
    /// @notice Number of tickets sold per game
    mapping(uint256 gameId => uint256) public ticketsSold;
    /// @notice Current jackpot (in wei)
    mapping(uint256 gameId => uint256) public jackpots;
    /// @notice Accrued community fee share (wei)
    uint256 public accruedCommunityFees;
    /// @notice Block timestamp of when the game started
    mapping(uint256 gameId => uint256) public gameStartedAt;

    event TicketPurchased(
        uint256 indexed gameId,
        address indexed whomst,
        uint256 indexed tokenId,
        uint8[] picks
    );
    event GameFinalised(uint256 gameId, uint8[] winningPicks);
    event Transferred(address to, uint256 value);

    error TransferFailure(address to, uint256 value, bytes reason);
    error InvalidNumPicks(uint256 numPicks);
    error InvalidGamePeriod(uint256 gamePeriod);
    error InvalidTicketPrice(uint256 ticketPrice);
    error InvalidRandomiser(address randomiser);
    error IncorrectPaymentAmount(uint256 paid, uint256 expected);
    error UnsortedPicks(uint8[] picks);
    error InvalidBallValue(uint256 ballValue);
    error GameAlreadyDrawn();
    error UnexpectedState(GameState actual, GameState expected);
    error RequestAlreadyInFlight(uint256 requestId, uint256 timestamp);
    error RequestIdOverflow(uint256 requestId);
    error CallerNotRandomiser(address caller);
    error RequestIdMismatch(uint256 actual, uint208 expected);
    error InsufficientRandomWords();
    error NoWin(uint256 pickId, uint256 winningPickId);
    error WaitLonger(uint256 deadline);

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 numPicks_,
        uint8 maxBallValue_,
        uint256 gamePeriod_,
        uint256 ticketPrice_,
        uint256 communityFeeBps_,
        address randomiser_
    ) payable ERC721(name_, symbol_) Ownable(msg.sender) {
        if (numPicks_ == 0) {
            revert InvalidNumPicks(numPicks_);
        }
        numPicks = numPicks_;
        maxBallValue = maxBallValue_;

        if (gamePeriod_ < 10 minutes) {
            revert InvalidGamePeriod(gamePeriod_);
        }
        gamePeriod = gamePeriod_;

        if (ticketPrice_ == 0) {
            revert InvalidTicketPrice(ticketPrice_);
        }
        ticketPrice = ticketPrice_;
        communityFeeBps = communityFeeBps_;

        if (randomiser_ == address(0)) {
            revert InvalidRandomiser(randomiser_);
        }
        randomiser = randomiser_;

        // Seed the jackpot
        jackpots[0] += msg.value;
        // The first game starts straight away
        gameStartedAt[0] = block.timestamp;
    }

    /// @notice Seed the jackpot
    function seedJackpot() external payable {
        // We allow seeding jackpot during purchase phase only, so we don't
        // have to fuck around with accounting
        if (gameState != GameState.Purchase) {
            revert UnexpectedState(gameState, GameState.Purchase);
        }
        jackpots[currentGameId] += msg.value;
    }

    /// @notice Compute the identity of an ordered set of numbers
    function computePickIdentity(
        uint8[] memory picks
    ) internal pure returns (uint256 id) {
        bytes memory packed = new bytes(picks.length);
        for (uint256 i; i < picks.length; ++i) {
            packed[i] = bytes1(picks[i]);
        }
        return uint256(keccak256(packed));
    }

    /// @notice Purchase a ticket
    /// @param tickets Tickets! Tickets!
    function purchase(Ticket[] calldata tickets) external payable {
        uint256 totalPrice = ticketPrice * tickets.length;
        if (msg.value != totalPrice) {
            revert IncorrectPaymentAmount(msg.value, totalPrice);
        }

        uint256 gameId = currentGameId;

        address whomst;
        uint8[] memory picks;
        for (uint256 t; t < tickets.length; ++t) {
            whomst = tickets[t].whomst;
            picks = tickets[t].picks;
            // Handle fee splits
            uint256 communityFeeShare = (msg.value * communityFeeBps) / 10000;
            accruedCommunityFees += communityFeeShare;
            jackpots[gameId] += msg.value - communityFeeShare;

            if (picks.length != numPicks) {
                revert InvalidNumPicks(picks.length);
            }

            // Assert picks are ascendingly sorted, with no possibility of duplicates
            uint8 lastPick;
            for (uint256 i = 0; i < numPicks; ++i) {
                uint8 pick = picks[i];
                if (pick <= lastPick) revert UnsortedPicks(picks);
                if (pick > maxBallValue) revert InvalidBallValue(pick);
                lastPick = pick;
            }
            // Record picked numbers
            uint256 tokenId = ++currentTokenId;
            tokenIdToTicket[tokenId] = picks;
            ticketsSold[gameId] += 1;
            _safeMint(whomst, tokenId);
            // Account for this pick set
            uint256 id = computePickIdentity(picks);
            tokenByPickIdentity[gameId][id].push(tokenId);
            emit TicketPurchased(gameId, whomst, tokenId, picks);
        }
    }

    /// @notice Draw numbers, picking potential jackpot winners and ending the
    ///     current game. This should be automated by a keeper.
    function draw() external {
        if (gameState != GameState.Purchase) {
            revert UnexpectedState(gameState, GameState.Purchase);
        }
        gameState = GameState.DrawPending;

        uint256 gameDeadline = (gameStartedAt[currentGameId] + gamePeriod);
        if (block.timestamp < gameDeadline) {
            revert WaitLonger(gameDeadline);
        }

        RandomnessRequest memory randReq = randomnessRequest;
        if (
            randReq.requestId != 0 &&
            (block.timestamp <= (randReq.timestamp + 1 hours))
        ) {
            revert RequestAlreadyInFlight(randReq.requestId, randReq.timestamp);
        }
        uint256 requestId = IRandomiserGen2(randomiser).getRandomNumber(
            address(this),
            500_000,
            6
        );
        if (requestId > type(uint208).max) {
            revert RequestIdOverflow(requestId);
        }
        randomnessRequest = RandomnessRequest({
            requestId: uint208(requestId),
            timestamp: uint48(block.timestamp)
        });
    }

    function receiveRandomWords(
        uint256 requestId,
        uint256[] calldata randomWords
    ) external {
        if (msg.sender != randomiser) {
            revert CallerNotRandomiser(msg.sender);
        }
        if (gameState != GameState.DrawPending) {
            revert UnexpectedState(gameState, GameState.DrawPending);
        }
        if (randomnessRequest.requestId != requestId) {
            revert RequestIdMismatch(requestId, randomnessRequest.requestId);
        }
        randomnessRequest = RandomnessRequest({requestId: 0, timestamp: 0});

        if (randomWords.length == 0) {
            revert InsufficientRandomWords();
        }

        // Pick numbers
        uint8[] memory balls = new uint8[](numPicks);
        for (uint256 i; i < numPicks; ++i) {
            balls[i] = uint8(
                1 +
                    FeistelShuffleOptimised.shuffle(
                        i,
                        maxBallValue,
                        randomWords[0],
                        4
                    )
            );
        }
        balls = balls.sort();
        uint256 gameId = currentGameId++;
        emit GameFinalised(gameId, balls);

        // Record winning pick identity only (constant 32B)
        winningPickIds[gameId] = computePickIdentity(balls);

        // Ready for next game
        gameState = GameState.Purchase;
    }

    /// @notice Claim a share of the jackpot with a winning ticket
    function claimWinnings(uint256 tokenId) external {
        address whomst = _ownerOf(tokenId);
        if (whomst == address(0)) {
            revert ERC721NonexistentToken(tokenId);
        }
        _burn(tokenId);

        // Check winning balls from game
        uint256 gameId = tokenIdToGameId[tokenId];
        uint256 winningPickId = winningPickIds[gameId];
        uint256 ticketPickId = computePickIdentity(tokenIdToTicket[tokenId]);
        if (winningPickId != ticketPickId) {
            revert NoWin(ticketPickId, winningPickId);
        }

        // Determine if the jackpot was won
        uint256 jackpot = jackpots[gameId];
        uint256 numWinners = tokenByPickIdentity[gameId][winningPickId].length;
        uint256 prizeShare;
        if (numWinners > 0) {
            // Transfer share of jackpot to ticket holder
            prizeShare = jackpot / numWinners;
        } else {
            // No jackpot winners :(
            // Jackpot is shared between all tickets
            prizeShare = jackpot / ticketsSold[gameId];
        }
        _transferOrBust(whomst, prizeShare);
    }

    /// @notice Withdraw accrued community fees
    function withdrawAccruedFees() external onlyOwner {
        uint256 totalAccrued = accruedCommunityFees;
        accruedCommunityFees = 0;
        _transferOrBust(msg.sender, totalAccrued);
    }

    /// @notice Transfer via raw call; revert on failure
    /// @param to Address to transfer to
    /// @param value Value (in wei) to transfer
    function _transferOrBust(address to, uint256 value) internal {
        (bool success, bytes memory retval) = to.call{value: value}("");
        if (!success) {
            revert TransferFailure(to, value, retval);
        }
        emit Transferred(to, value);
    }
}
