// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Combinations} from "./lib/Combinations.sol";
import {BitSet} from "./lib/BitSet.sol";
import {FeistelShuffleOptimised} from "./lib/FeistelShuffleOptimised.sol";
import {Sort} from "./lib/Sort.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IRandomiserCallback} from "./interfaces/IRandomiserCallback.sol";
import {IAnyrand} from "./interfaces/IAnyrand.sol";

/// @title Lootery
/// @notice Lotto the ultimate
contract Lootery is
    IRandomiserCallback,
    Initializable,
    OwnableUpgradeable,
    ERC721Upgradeable
{
    using Sort for uint8[];
    using BitSet for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;

    /// @notice Current state of the lootery
    enum GameState {
        /// @notice This is the only state where the jackpot can increase
        Purchase,
        /// @notice Waiting for VRF fulfilment
        DrawPending
    }

    struct CurrentGame {
        /// @notice aka uint8
        GameState state;
        /// @notice current gameId
        uint248 id;
    }

    /// @notice A ticket to be purchased
    struct Ticket {
        /// @notice For whomst shall this purchase be made out
        address whomst;
        /// @notice Lotto numbers, pick wisely! Picks must be ASCENDINGLY
        ///     ORDERED, with NO DUPLICATES!
        uint8[] pick;
    }

    struct Game {
        /// @notice Number of tickets sold per game
        uint64 ticketsSold;
        /// @notice Timestamp of when the game started
        uint64 startedAt;
        /// @notice Number of winning tix, including ALL tiers
        uint64 numWinners;
        /// @notice Winning pick
        uint8[] winningPick;
    }

    /// @notice An already-purchased ticket, assigned to a tokenId
    struct PurchasedTicket {
        /// @notice gameId that ticket is valid for
        uint256 gameId;
        uint8[] pick;
    }

    /// @notice Describes an inflight randomness request
    struct RandomnessRequest {
        uint208 requestId;
        uint48 timestamp;
    }

    struct TierInfo {
        bool isPresent;
        uint248 tier;
        uint256 numWinners;
    }

    /// @notice How many numbers must be picked per draw (and per ticket)
    ///     The range of this number should be something like 3-7
    uint8 public numPicks;
    /// @notice Maximum value of a ball (pick) s.t. value \in [1, maxBallValue]
    uint8 public maxBallValue;
    /// @notice How long a game lasts in seconds (before numbers are drawn)
    uint256 public gamePeriod;
    /// @notice Trusted randomiser
    address public randomiser;
    /// @notice Token used for prizes
    address public prizeToken;
    /// @notice Ticket price
    uint256 public ticketPrice;
    /// @notice Percentage of ticket price directed to the community
    uint256 public communityFeeBps;
    /// @notice Minimum seconds to wait between seeding jackpot
    uint256 public seedJackpotDelay;

    /// @dev Current token id
    uint256 private currentTokenId;
    /// @notice Current state of the game
    CurrentGame public currentGame;
    /// @notice Running jackpot
    uint256 public jackpot;
    /// @notice Current random request details
    RandomnessRequest public randomnessRequest;
    /// @notice token id => purchased ticked details (gameId, pickId)
    mapping(uint256 tokenId => PurchasedTicket) public purchasedTickets;
    /// @notice Mapping of picksets to respective total count, separated by gameId
    mapping(uint256 gameId => mapping(uint256 pickSet => uint256 count))
        public pickSetCounts;
    /// @notice Set of winning picks per game, mapped to tier
    mapping(uint256 gameId => mapping(uint256 pickSet => TierInfo))
        public winningPickSetTiers;
    /// @notice Game data
    mapping(uint256 gameId => Game) public gameData;
    /// @notice Accrued community fee share (wei)
    uint256 public accruedCommunityFees;
    /// @notice When nonzero, this gameId will be the last
    uint256 public apocalypseGameId;
    /// @notice Timestamp of when jackpot was last seeded
    uint256 public jackpotLastSeededAt;
    /// @notice Array of tier shares (bps). Sum of all elements MUST add up to
    ///     a maximum of 100_00 bps.
    uint64[] public tierSharesBps;

    event TicketPurchased(
        uint256 indexed gameId,
        address indexed whomst,
        uint256 indexed tokenId,
        uint8[] picks
    );
    event GameFinalised(uint256 gameId, uint8[] winningPicks);
    event Transferred(address to, uint256 value);
    event WinningsClaimed(
        uint256 indexed tokenId,
        uint256 indexed gameId,
        address whomst,
        uint256 value
    );
    event ConsolationClaimed(
        uint256 indexed tokenId,
        uint256 indexed gameId,
        address whomst,
        uint256 value
    );
    event DrawSkipped(uint256 indexed gameId);
    event Received(address sender, uint256 amount);
    event JackpotSeeded(address indexed whomst, uint256 amount);

    error TransferFailure(address to, uint256 value, bytes reason);
    error InvalidNumPicks(uint256 numPicks);
    error InvalidGamePeriod(uint256 gamePeriod);
    error InvalidTicketPrice(uint256 ticketPrice);
    error InvalidRandomiser(address randomiser);
    error InvalidPrizeToken(address prizeToken);
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
    error NoWin(uint256 pickSet, uint256 winningPickSet);
    error WaitLonger(uint256 deadline);
    error TicketsSoldOverflow(uint256 value);
    error InsufficientOperationalFunds(uint256 have, uint256 want);
    error ClaimWindowMissed(uint256 tokenId);
    error GameInactive();
    error RateLimited(uint256 secondsToWait);

    constructor() {
        _disableInitializers();
    }

    /// @notice Initialisoooooooor
    function init(
        address owner_,
        string memory name_,
        string memory symbol_,
        uint8 numPicks_,
        uint8 maxBallValue_,
        uint256 gamePeriod_,
        uint256 ticketPrice_,
        uint256 communityFeeBps_,
        address randomiser_,
        address prizeToken_,
        uint256 seedJackpotDelay_
    ) public initializer {
        __Ownable_init(owner_);
        __ERC721_init(name_, symbol_);

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

        if (prizeToken_ == address(0)) {
            revert InvalidPrizeToken(prizeToken_);
        }
        prizeToken = prizeToken_;

        seedJackpotDelay = seedJackpotDelay_;

        // TODO: This should be configurable, also:
        // - sum of all elements must <= 100_00
        // - cardinality must <= numPicks
        tierSharesBps.push(12_80); //   tier 0 (5 balls)
        tierSharesBps.push(10_00); //   tier 1 (4 balls)
        tierSharesBps.push(5_00); //    tier 3 (3 balls)

        gameData[0] = Game({
            ticketsSold: 0,
            // The first game starts straight away
            startedAt: uint64(block.timestamp),
            numWinners: 0,
            winningPick: new uint8[](numPicks)
        });
    }

    function isGameActive() public view returns (bool) {
        uint256 apocalypseGameId_ = apocalypseGameId;
        return !(apocalypseGameId_ != 0 && currentGame.id >= apocalypseGameId_);
    }

    function _assertGameIsActive() internal view {
        if (!isGameActive()) {
            revert GameInactive();
        }
    }

    /// @notice Seed the jackpot
    function seedJackpot(uint256 value) external {
        _assertGameIsActive();
        // We allow seeding jackpot during purchase phase only, so we don't
        // have to fuck around with accounting
        if (currentGame.state != GameState.Purchase) {
            revert UnexpectedState(currentGame.state, GameState.Purchase);
        }

        // Rate limit seeding the jackpot
        if (block.timestamp < jackpotLastSeededAt + seedJackpotDelay) {
            revert RateLimited(
                jackpotLastSeededAt + seedJackpotDelay - block.timestamp
            );
        }
        jackpotLastSeededAt = block.timestamp;

        jackpot += value;
        IERC20(prizeToken).safeTransferFrom(msg.sender, address(this), value);
        emit JackpotSeeded(msg.sender, value);
    }

    /// @notice Compute the identity of an ordered set of numbers
    function getWinningPick(
        uint256 gameId
    ) external view returns (uint8[] memory) {
        return gameData[gameId].winningPick;
    }

    /// @notice Compute the winning BALLS given a random seed
    /// @param randomSeed Seed that determines the permutation of BALLS
    function computeWinningBalls(
        uint256 randomSeed
    ) public view returns (uint8[] memory balls) {
        balls = new uint8[](numPicks);
        for (uint256 i; i < numPicks; ++i) {
            balls[i] = uint8(
                1 +
                    FeistelShuffleOptimised.shuffle(
                        i,
                        maxBallValue,
                        randomSeed,
                        4
                    )
            );
        }
        balls = balls.sort();
    }

    /// @notice Purchase a ticket
    /// @param tickets Tickets! Tickets!
    function purchase(Ticket[] calldata tickets) external {
        uint256 ticketsCount = tickets.length;
        uint256 totalPrice = ticketPrice * ticketsCount;

        IERC20(prizeToken).safeTransferFrom(
            msg.sender,
            address(this),
            totalPrice
        );

        // Handle fee splits
        uint256 communityFeeShare = (totalPrice * communityFeeBps) / 10000;
        uint256 jackpotShare = totalPrice - communityFeeShare;
        accruedCommunityFees += communityFeeShare;

        _pickTickets(tickets, jackpotShare);
    }

    /// @notice Draw numbers, picking potential jackpot winners and ending the
    ///     current game. This should be automated by a keeper.
    function draw() external {
        _assertGameIsActive();
        // Assert game is still playable
        // Assert we're in the correct state
        CurrentGame memory currentGame_ = currentGame;
        if (currentGame_.state != GameState.Purchase) {
            revert UnexpectedState(currentGame_.state, GameState.Purchase);
        }
        Game memory game = gameData[currentGame_.id];
        // Assert that the game is actually over
        uint256 gameDeadline = (game.startedAt + gamePeriod);
        if (block.timestamp < gameDeadline) {
            revert WaitLonger(gameDeadline);
        }

        // Assert that there are actually tickets sold in this game
        // slither-disable-next-line incorrect-equality
        if (game.ticketsSold == 0) {
            // Case #1: No tickets sold; just transition to the next game
            uint248 nextGameId = currentGame_.id + 1;
            currentGame = CurrentGame({
                state: GameState.Purchase, // redundant, but inconsequential
                id: nextGameId
            });
            emit DrawSkipped(currentGame_.id);
            return;
        }

        // Case #2: Tickets were sold
        currentGame.state = GameState.DrawPending;
        // Assert there's not already a request inflight, unless some
        // reasonable amount of time has already passed
        RandomnessRequest memory randReq = randomnessRequest;
        if (
            randReq.requestId != 0 &&
            (block.timestamp <= (randReq.timestamp + 1 hours))
        ) {
            revert RequestAlreadyInFlight(randReq.requestId, randReq.timestamp);
        }

        // Assert that we have enough in operational funds so as to not eat
        // into jackpots or whatever else.
        uint256 requestPrice = IAnyrand(randomiser).getRequestPrice(500_000);
        if (address(this).balance < requestPrice) {
            revert InsufficientOperationalFunds(
                accruedCommunityFees,
                requestPrice
            );
        }
        // VRF call to trusted coordinator
        // slither-disable-next-line reentrancy-eth,arbitrary-send-eth
        uint256 requestId = IAnyrand(randomiser).requestRandomness{
            value: requestPrice
        }(block.timestamp + 30, 500_000);
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
        if (currentGame.state != GameState.DrawPending) {
            revert UnexpectedState(currentGame.state, GameState.DrawPending);
        }
        if (randomnessRequest.requestId != requestId) {
            revert RequestIdMismatch(requestId, randomnessRequest.requestId);
        }
        randomnessRequest = RandomnessRequest({requestId: 0, timestamp: 0});

        if (randomWords.length == 0) {
            revert InsufficientRandomWords();
        }

        // Pick numbers
        uint8[] memory balls = computeWinningBalls(randomWords[0]);
        uint248 gameId = currentGame.id;
        emit GameFinalised(gameId, balls);

        // Sum number of winners including ALL tiers
        uint256 numWinners;
        uint256 numTiers = tierSharesBps.length;
        for (uint256 tier; tier < numTiers; ++tier) {
            // Generate combinations for this tier
            uint8[][] memory combos = Combinations.genCombinations(
                balls,
                numPicks - tier
            );
            uint256 numWinnersInTier;
            for (uint256 c; c < combos.length; ++c) {
                uint256 comboPickSet = BitSet.from(combos[c]);
                uint256 numComboWinners = pickSetCounts[gameId][comboPickSet];
                numWinnersInTier += numComboWinners;
                numWinners += numComboWinners;
                winningPickSetTiers[gameId][comboPickSet] = TierInfo({
                    isPresent: true,
                    tier: uint248(tier),
                    numWinners: numWinnersInTier
                });
            }
        }
        // Record number of winners & winning pick
        Game memory game = gameData[gameId];
        gameData[gameId] = Game({
            ticketsSold: game.ticketsSold,
            startedAt: game.startedAt,
            numWinners: uint64(numWinners),
            winningPick: balls
        });

        // Ready for next game
        currentGame = CurrentGame({state: GameState.Purchase, id: gameId + 1});

        // Set up next game; roll over jackpot
        gameData[gameId + 1] = Game({
            ticketsSold: 0,
            startedAt: uint64(block.timestamp),
            numWinners: 0,
            winningPick: new uint8[](numPicks)
        });
    }

    /// @notice Claim a share of the jackpot with a winning ticket
    /// @param tokenId Token id of the ticket (will be burnt)
    function claimWinnings(uint256 tokenId) external {
        address whomst = _ownerOf(tokenId);
        if (whomst == address(0)) {
            revert ERC721NonexistentToken(tokenId);
        }
        // Burning the token is our "claim nullifier"
        _burn(tokenId);

        PurchasedTicket memory ticket = purchasedTickets[tokenId];
        uint256 currentGameId = currentGame.id;
        // Can only claim winnings from the last game
        if (ticket.gameId != currentGameId - 1) {
            revert ClaimWindowMissed(tokenId);
        }
        uint256 ticketPickSet = BitSet.from(ticket.pick);

        // Determine if the jackpot was won
        Game memory prevGame = gameData[ticket.gameId];
        // Case 1: no winners in apocalypse mode
        if (prevGame.numWinners == 0 && !isGameActive()) {
            // No jackpot winners, and game is no longer active!
            // Jackpot is shared between all tickets
            // Invariant: `ticketsSold[gameId] > 0`
            uint256 prizeShare = jackpot / prevGame.ticketsSold;
            _transferOrBust(whomst, prizeShare);
            emit ConsolationClaimed(tokenId, ticket.gameId, whomst, prizeShare);
            return;
        }
        // Case 2: there are winners, so check if ticket is a winner
        TierInfo memory tierInfo = winningPickSetTiers[ticket.gameId][
            ticketPickSet
        ];
        if (tierInfo.isPresent) {
            // Calculate payout
            uint256 tierShareBps = tierSharesBps[tierInfo.tier];
            uint256 prizeShare = (jackpot * tierShareBps) /
                (100_00 * tierInfo.numWinners);
            // TODO: Check that this math works out
            pickSetCounts[ticket.gameId][ticketPickSet] -= 1;
            jackpot -= prizeShare;
            _transferOrBust(whomst, prizeShare);
            emit WinningsClaimed(tokenId, ticket.gameId, whomst, prizeShare);
        }
        // Case 3: ticket is not a winner
        revert NoWin(ticketPickSet, BitSet.from(prevGame.winningPick));
    }

    /// @notice Withdraw accrued community fees
    function withdrawAccruedFees() external onlyOwner {
        uint256 totalAccrued = accruedCommunityFees;
        accruedCommunityFees = 0;
        _transferOrBust(msg.sender, totalAccrued);
    }

    /// @notice Allow owner to pick tickets for free
    function ownerPick(Ticket[] calldata tickets) external onlyOwner {
        _pickTickets(tickets, 0);
    }

    /// @notice Set the next game as the last game of the lottery
    function kill() external onlyOwner {
        if (apocalypseGameId != 0) {
            // Already set
            revert GameInactive();
        }

        CurrentGame memory currentGame_ = currentGame;
        if (currentGame_.state != GameState.Purchase) {
            revert UnexpectedState(currentGame_.state, GameState.Purchase);
        }
        apocalypseGameId = currentGame_.id + 1;
    }

    function rescueETH() external onlyOwner {
        (bool success, bytes memory data) = msg.sender.call{
            value: address(this).balance
        }("");
        if (!success) {
            revert TransferFailure(msg.sender, address(this).balance, data);
        }
    }

    /// @notice Allow owner to rescue any tokens sent to the contract; excluding jackpot and accrued fees
    function rescueTokens(address tokenAddress) external onlyOwner {
        uint256 amount = IERC20(tokenAddress).balanceOf(address(this));
        if (tokenAddress == prizeToken) {
            amount = amount - accruedCommunityFees - jackpot;
        }

        IERC20(tokenAddress).safeTransfer(msg.sender, amount);
    }

    /// @notice Transfer via raw call; revert on failure
    /// @param to Address to transfer to
    /// @param value Value (in wei) to transfer
    function _transferOrBust(address to, uint256 value) internal {
        IERC20(prizeToken).safeTransfer(to, value);
    }

    /// @notice Pick tickets and increase jackpot
    function _pickTickets(
        Ticket[] calldata tickets,
        uint256 jackpotShare
    ) internal {
        CurrentGame memory currentGame_ = currentGame;
        uint256 currentGameId = currentGame_.id;
        // Assert game is still playable
        _assertGameIsActive();

        uint256 ticketsCount = tickets.length;
        Game memory game = gameData[currentGameId];
        if (uint256(game.ticketsSold) + ticketsCount > type(uint64).max) {
            revert TicketsSoldOverflow(
                uint256(game.ticketsSold) + ticketsCount
            );
        }
        jackpot += jackpotShare;
        gameData[currentGameId] = Game({
            ticketsSold: game.ticketsSold + uint64(ticketsCount),
            startedAt: game.startedAt,
            numWinners: game.numWinners,
            winningPick: game.winningPick
        });

        uint256 numPicks_ = numPicks;
        uint256 maxBallValue_ = maxBallValue;
        uint256 startingTokenId = currentTokenId + 1;
        currentTokenId += ticketsCount;
        for (uint256 t; t < ticketsCount; ++t) {
            address whomst = tickets[t].whomst;
            uint8[] memory pick = tickets[t].pick;

            if (pick.length != numPicks_) {
                revert InvalidNumPicks(pick.length);
            }

            // Assert picks are ascendingly sorted, with no possibility of duplicates
            uint8 lastBall;
            for (uint256 i; i < numPicks_; ++i) {
                uint8 ball = pick[i];
                if (ball <= lastBall) revert UnsortedPicks(pick);
                if (ball > maxBallValue_) revert InvalidBallValue(ball);
                lastBall = ball;
            }

            // Record picked numbers
            uint256 tokenId = startingTokenId + t;
            purchasedTickets[tokenId] = PurchasedTicket({
                gameId: currentGameId,
                pick: pick
            });

            // Account for all combinations in all relevant tiers
            uint256 numTiers = tierSharesBps.length;
            for (uint256 m; m < numTiers; ++m) {
                uint8[][] memory combos = Combinations.genCombinations(
                    pick,
                    numPicks - m
                );
                for (uint256 c; c < combos.length; ++c) {
                    uint256 pickId = uint256(
                        keccak256(abi.encodePacked(combos[c]))
                    );
                    pickSetCounts[currentGameId][pickId] += 1;
                }
            }
            emit TicketPurchased(currentGameId, whomst, tokenId, pick);
        }
        // Effects
        for (uint256 t; t < ticketsCount; ++t) {
            address whomst = tickets[t].whomst;
            _safeMint(whomst, startingTokenId + t);
        }
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        _requireOwned(tokenId);
        return
            "ipfs://bafkreice6o7ptnfe5fljfher65lmcvscc634iehybmxafwv7hkrkyktmem";
    }
}
