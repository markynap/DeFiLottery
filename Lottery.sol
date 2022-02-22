// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./IERC20.sol";
import "./ILotteryTicket.sol";

contract Lottery {

    // Token used to buy tickets + reward to winners
    IERC20 token;

    // Ticket NFTs
    ILotteryTicket nft_;

    // Random Number Generator
    IRNG random;

    // Lottery is between 0-9
    uint256 public constant MAX_LOTTERY_NUMBER = 9;
    
    // Lottery has 5 numbers per ticket
    uint256 public constant NUMBERS_PER_TICKET = 5;

    // 24 hours per lottery
    uint256 public LOTTERY_DURATION = 28800;

    // cost in Token per Lottery Ticket
    uint256 public costPerTicket = 10**4 * 10**9;

    // Request ID for random number
    bytes32 internal requestId_;
    // Counter for lottery IDs 
    uint256 private lotteryIdCounter_;

    // Prize Distributions
    uint8[] public prizeDistributions;

    // Developer Cut 
    uint256 public devCut = 20;

    // Lottery Statuses
    enum Status {
        Open,
        Closed,
        Completed
    }

    struct Guesser {
        bool includedInArray;
        uint256[] chosenNumbers; // replace this with the TokenID of the NFT
        uint256 timesGuessed; // maybe include full guess or tokenID # of GuessNFT to search for numbers
    }

    struct Guess {
        uint256 numberOfGuesses;
        address[] callers;
        mapping ( address => Guesser ) guesser;
    }

    // Number -> NumberPlacementArray
    mapping ( uint256 => Guess[NUMBERS_PER_TICKET]) guesses;

    // user -> LotteryID -> claim amount
    mapping ( address => mapping ( uint256 => uint256 )) userClaimByLotteryID;


    // Loterry Data
    struct LotteryData {
        uint256 lotteryID;
        Status lotteryStatus;
        uint256 prizePool;
        uint256 costPerTicket;
        uint256 startTime;
        uint256 endTime;
        uint16[] winningNumbers;
    }

    // ID => LotteryData
    mapping ( uint256 => LotteryData ) public lotteries;

    // User -> Approved Function Caller
    mapping ( address => bool ) public isApprovedCaller;

    modifier onlyRandomGenerator(){
        require(msg.sender == address(random), 'Only RNG Can Call');
        _;
    }

    modifier onlyApproved() {
        require(isApprovedCaller[msg.sender], 'Only Approved');
        _;
    }

    modifier notContract() {
        require(!address(msg.sender).isContract(), "contract not allowed");
        require(msg.sender == tx.origin, "proxy contract not allowed");
       _;
    }

    event TicketsPurchased(
        address indexed minter,
        uint256[] ticketIDs,
        uint16[] numbers,
        uint256 cost
    );

    constructor(){

        // initialize token
        token = IERC20(0xA67a13c9283Da5AABB199Da54a9Cb4cD8B9b16bA);

        // initialize Ticket NFTs
        nft_ = IERC721(0xA67a13c9283Da5AABB199Da54a9Cb4cD8B9b16bA);

        // initialize RNG
        random = IRNG(0xA67a13c9283Da5AABB199Da54a9Cb4cD8B9b16bA);

        // approve caller as first owner
        isApprovedCaller[msg.sender] = true;

        prizeDistributions[0] = 5;   // 5% for one winning number
        prizeDistributions[1] = 10;  // 10% for two winning numbers
        prizeDistributions[2] = 15;  // 15% for three winning numbers
        prizeDistributions[3] = 20;  // 20% for four winning numbers
        prizeDistributions[4] = 30;  // 30% for five winning numbers
    }


    ///////////////////////////////////////////
    //////////    OWNER FUNCTIONS    //////////
    ///////////////////////////////////////////
    
    function approveCaller(address caller, bool isApproved) external onlyOwner {
        require(caller != address(0));
        isApprovedCaller[caller] = isApproved;
    }

    function setRNG(address _rng) external onlyOwner {
        require(_rng != address(0), 'Zero Address');
        random = IRNG(_rng);
    }

    function setDevCut(uint256 _devCut) external onlyOwner {
        require(_devCut <= 50, 'Dev Cut Too Large');
        devCut = _devCut;
    }

    function setTicketNFTContract(address nft) external onlyOwner {
        require(nft != address(0));
        nft_ = ILotteryTicket(nft);
    }

    function withdraw(uint256 amount) external onlyOwner {
        token.transfer(
            msg.sender, amount
        );
    }

    function setLotteryDuration(uint256 duration) external onlyOwner {
        require(duration > 0 && duration < 10**7, 'Duration Out Of Bounds');
        LOTTERY_DURATION = duration;
    }

    function setDistributions(uint8[] calldata distributions) external onlyOwner {
        require(distributions.length == NUMBERS_PER_TICKET, 'Invalid Size');
        uint256 total = 0;
        for (uint i = 0; i < distributions.length; i++) {
            prizeDistributions[i] = distributions[i];
            total += uint256(distributions[i]);
        }
        require(total == 100, 'Invalid Distribution');
    }

    function setCostPerTicket(uint256 _costPerTicket) external onlyOwner {
        require(_costPerTicket > 0, 'Cannot Have Zero Cost');
        costPerTicket = _costPerTicket;
    }

    /**
        Starts The Next Lottery Based On Current State Values
     */
    function startNextLottery() external onlyOwner {

        lotteryIdCounter_ = lotteryIdCounter_.add(1);

        uint16[] memory winningNumbers = new uint16[](NUMBERS_PER_TICKET);

        lotteries[lotteryIdCounter_] = LotteryData({
            lotteryIdCounter_,
            Status.Open,
            0,
            costPerTicket,
            block.number,
            block.number + LOTTERY_DURATION,
            winningNumbers
        });
    }


    // called by approved owner to queue the winning numbers from the RNG Contract
    // The contract calls numbersDrawn() after the random number has been fetched
    function drawWinningNumbers(
        uint256 _lotteryId, 
        uint256 _seed
    ) 
        external 
        onlyApproved
    {
        // Checks that the lottery is past the closing block
        require(
            lotteries[_lotteryId].endTime <= block.number,
            "Lottery Has Not Ended"
        );
        // Checks lottery numbers have not already been drawn
        require(
            lotteries[_lotteryId].lotteryStatus == Status.Open,
            "Lottery State Not Open"
        );
        // Sets lottery status to closed
        lotteries[_lotteryId].lotteryStatus = Status.Closed;
        // Requests a random number from the generator
        requestId_ = random.getRandomNumber(_lotteryId, _seed);
        // Emits that random number has been requested
        emit RequestNumbers(_lotteryId, requestId_);
    }

    function numbersDrawn(
        uint256 _lotteryId,
        bytes32 _requestId, 
        uint256 _randomNumber
    ) 
        external
        onlyRandomGenerator
    {
        require(
            allLotteries_[_lotteryId].lotteryStatus == Status.Closed,
            "Draw numbers first"
        );
        if(requestId_ == _requestId) {
            allLotteries_[_lotteryId].lotteryStatus = Status.Completed;
            allLotteries_[_lotteryId].winningNumbers = _split(_randomNumber);
        }

        // take dev cut out of pot
        _takeDevCut(_lotteryId);

        // assign remainder of pot to winners
        _assignPotToWinners();

        // clean up already included mapping
        for (uint i = 0; i < MAX_LOTTERY_NUMBER+1; i++) {
            for (uint j = 0; j < NUMBERS_PER_TICKET; j++) {
                delete guesses[i][j].alreadyIncluded;
            }
        }
        // delete guesses mapping
        delete guesses;

        emit LotteryClose(_lotteryId, nft_.getTotalSupply());
    }



    ///////////////////////////////////////////
    /////////    PUBLIC FUNCTIONS    //////////
    ///////////////////////////////////////////


    function buyBatchTicket(uint256 _lotteryId, uint256 numberOfTickets, uint16[] calldata numbersChosen) external notContract {
        require(
            lotteries[_lotteryId].lotteryStatus == Status.Open,
            "Lottery Not Open"
        );
        require(
            lotteries[_lotteryId].startTime <= block.number,
            'Lottery Has Not Started'
        );
        require(
            lotteries[_lotteryId].endTime > block.number,
            'Lottery Has Ended'
        );
        require(
            numberOfTickets > 0 && numberOfTickets <= 50,
            'Invalid Batch Ticket Range'
        );
        require(
            numbersChosen.length == NUMBERS_PER_TICKET.mul(numberOfTickets),
            'Invalid Ticket Length'
        );

        _transferInAndMint(_lotteryId, msg.sender, numberOfTickets, numbersChosen);
    }

    function claimWinnings(uint256 _lotteryId, uint256 _tokenID) external notContract {

        require(
            lotteries[_lotteryId].endTime <= block.number,
            'Lottery Has Not Ended'
        );

        require(
            lotteries[_lotteryId].lotteryStatus = Status.Completed,
            'Winning Numbers Not Chosen'
        );

        require(
            nft_.getOwnerOfTicket(_tokenId) == msg.sender,
            'Only Ticket Owner Can Claim'
        );

        // Sets the claim of the ticket to true (if claimed, will revert)
        require(
            nft_.claimTicket(_tokenId, _lotteryId),
            "Numbers for ticket invalid"
        );

        // Getting the number of matching tickets
        uint8 matchingNumbers = _getNumberOfMatching(
            nft_.getTicketNumbers(_tokenId),
            lotteries[_lotteryId].winningNumbers
        );
        // Getting the prize amount for those matching tickets
        uint256 prizeAmount = _prizeForMatching(
            matchingNumbers,
            _lotteryId
        );
        require(
            prizeAmount > 0,
            'No Prize To Claim'
        );
        // Removing the prize amount from the pool
        lotteries[_lotteryId].prizePool = lotteries[_lotteryId].prizePool.sub(prizeAmount);
        // Transfering the user their winnings
        token.transfer(msg.sender, prizeAmount);
    }

    ///////////////////////////////////////////
    //////////    READ FUNCTIONS    ///////////
    ///////////////////////////////////////////


    function costToBuyTickets(
        uint256 _lotteryId,
        uint256 _numberOfTickets
    ) external view returns(uint256) {
        return lotteries[_lotteryId].costPerTicket.mul(_numberOfTickets);
    }




    ///////////////////////////////////////////
    ////////    INTERNAL FUNCTIONS    /////////
    ///////////////////////////////////////////

    function _takeDevCut(uint256 _lotteryID) internal {
        uint256 cut = ( lotteries[_lotteryID].prizePool * devCut ) / 100;
        if (cut > 0) {
            lotteries[_lotteryID].prizePool = lotteries[_lotteryID].prizePool.sub(cut);
            token.transfer(devAddr, cut);
        }
    }

    function _assignPotToWinners(uint16[] memory _winningNumbers) internal {

        // iterate through winning number positions
        // calculate how many users have guessed 1-5 correctly
            // Find some algorithm to determine the # of correct guesses
            // If User gets position 1 and 5 correct, iterate the 2nd index in correctGuesses mapping
        // based on how many have guessed x numbers correctly, split up pot between participants
        // save their claim amounts in userClaimByLotteryID state for future claiming

        // Number of correctly guessed positions
            // If user guesses 5 numbers, increment fifth element of array
            // If user guesses 1 number, increment first element of array
        uint256[] memory correctGuesses = new uint256[](NUMBERS_PER_TICKET);

        // user -> LotteryID -> claim amount
        //mapping ( address => mapping ( uint256 => uint256 )) userClaimByLotteryID;
        
        // User -> numberChosen[timesGuessed0, timesGuessed1, timesGuessed2, timesGuessed3 ...]
        mapping ( address => uint256[NUMBERS_PER_TICKET] ) timesGuessedChosenNumber;
        address[] memory allSuccessfulGuessers;
        struct EvaluatedGuesser {
            bool isSuccessful;
            uint256[] nWinningTickets; // [ 1, 4, 5 ] means they got 1 correct on one ticket, 4 on another, and 5 on another
        }
        mapping ( address => EvaluatedGuesser ) successfulGuessers;

        // loop through winning numbers
        for (uint i = 0; i < _winningNumbers.length; i++) {

            // for each winning number, fetch guesses that match placement
            uint16 winningNo = _winningNumbers[i];

            // if guesses are greater than zero
            if (guesses[winningNo][i].numberOfGuesses > 0) {

                // iterate through callers
                for (uint j = 0; j < guesses[winningNo][i].callers.length; j++) {
                    
                    // log times guesser has guessed + add to array
                    address guesser_ = guesses[winningNo][i].callers[j];
                    timesGuessedChosenNumber[guesser_][i] += guesses[winningNo][i].guesser[guesser_].timesGuessed;

                    if (!successfulGuesser[guesser_]) {
                        allSuccessfulGuessers.push(guesser_);
                        successfulGuessers[guesser_] = true;
                    }
                }
            }
        }

        // loop through guessers
        for (uint i = 0; i < allSuccessfulGuessers; i++) {

            address guesser_ = allSuccessfulGuessers[i];
            // max time placement guessed correctly
            uint256 MAX = 0;

            for (uint j = 0; j < _winningNumbers.length; j++) {
                if (timesGuessedChosenNumber[guesser_][j] > MAX) {
                    MAX = timesGuessedChosenNumber[guesser_][j];
                }
            }

            for (uint j = 0; j < MAX; j++) {

                // how many sets do we have
                uint256 numSets = _calculatelargestSet(timesGuessedChosenNumber[guesser_]);

                // increment winning set amount
                correctGuesses[numSets]++;

                // decrement all sets by 1
                timesGuessedChosenNumber[guesser_] = _decrement(timesGuessedChosenNuber[guesser_]);
            }

        }

        // iterate through correct guesses and calculate total pot

    }


    function _hasSet(uint256[] calldata timesGuessed, uint256 limit) internal pure returns (bool s) {

        s = true;
        for (uint i = 0; i < limit; i++) {
            s = s && timesGuessed[i] > 0;
        }
    }

    /**

        struct Guesser {
            bool includedInArray;
            uint256[] chosenNumbers;
            uint256 timesGuessed; // maybe include full guess or tokenID # of GuessNFT to search for numbers
        }

        struct Guess {
            uint256 numberOfGuesses;
            address[] callers;
            mapping ( address => Guesser ) guesser;
        }

        // Number -> NumberPlacementArray
        mapping ( uint256 => Guess[NUMBERS_PER_TICKET]) guesses;

     */

    function _transferIn(uint256 cost) internal {
        
        require(
            token.transferFrom(
                from,
                address(this),
                cost
            ),
            'Failure On Ticket Purchase'
        );

        // add amount to prize pool
        lotteries[ID].prizePool = lotteries[ID].prizePool.add(cost);
    }

    function _logGuesses(uint256 ID, address from, uint16[] calldata chosenNumbers) internal {

        // log guess data
        for (uint i = 0; i < chosenNumbers.length; i++) {
            
            // number chosen
            uint256 guess = chosenNumbers[i];
            require(guess <= MAX_LOTTERY_NUMBER, 'Guess Out Of Range');

            // number placement in ticket
            uint256 placement = i % NUMBERS_PER_TICKET;

            // copy chosen numbers over
            guesses[guess][placement].guesser[from].chosenNumbers = chosenNumbers;

            // increment number of guesses
            guesses[guess][placement].numberOfGuesses++;

            // if from has not guessed this before, add them to array
            if (!guesses[guess][placement].guessers[from].includedInArray) {
                guesses[guess][placement].callers.push(from);
                guesses[guess][placement].guessers[from].includedInArray = true;
            }

            // number of times From has guessed this placement
            guesses[guess][placement].guessers[from].timesGuessed++;
        }

    }

    function _transferInAndMint(uint256 ID, address from, uint256 numberOfTickets, uint16[] calldata chosenNumbers) internal {

        // log each guess
        for (uint i = 0; i < numberOfTickets.length; i++) {
            _logGuesses(ID, from, chosenNumbers[(i/NUMBERS_PER_TICKET)*NUMBERS_PER_TICKET : (i/NUMBERS_PER_TICKET + 1)*NUMBERS_PER_TICKET]);
        }

        // cost of tickets
        uint256 cost = lotteries[ID].costPerTicket.mul(numberOfTickets);

        // transfer in tokens
        _transferIn(cost);

        // Batch mint the user their ticket NFTs
        uint256[] memory ticketIds = nft_.batchMint(
            from,
            ID,
            numberOfTickets,
            chosenNumbers,
            NUMBERS_PER_TICKET
        );

        // Emit all information
        emit TicketsPurchased(
            from,
            ticketIds,
            chosenNumbers,
            cost,
        );

    }


    function _getNumberOfMatching(
        uint16[] memory _usersNumbers, 
        uint16[] memory _winningNumbers
    )
        internal
        pure
        returns(uint8 noOfMatching)
    {
        // Loops through all wimming numbers
        for (uint256 i = 0; i < _winningNumbers.length; i++) {
            // If the winning numbers and user numbers match
            if(_usersNumbers[i] == _winningNumbers[i]) {
                // The number of matching numbers incrases
                noOfMatching += 1;
            }
        }
    }

    /**
     * @param   _noOfMatching: The number of matching numbers the user has
     * @param   _lotteryId: The ID of the lottery the user is claiming on
     * @return  uint256: The prize amount in cake the user is entitled to 
     */
    function _prizeForMatching(
        uint8 _noOfMatching,
        uint256 _lotteryId
    ) internal view returns(uint256) {

        // CHANGE THIS TO BE MORE FAIR, NOT FIRST COME FIRST SERVE

        // If user has no matching numbers their prize is 0
        if(_noOfMatching == 0) {
            return 0;
        } 
        // Getting the percentage of the pool the user has won
        uint256 perOfPool = prizeDistributions[_noOfMatching-1];
        // Timesing the percentage one by the pool
        uint256 prize = lotteries[_lotteryId].prizePool.mul(perOfPool);
        // Returning the prize divided by 100 (as the prize distribution is scaled)
        return prize.div(100);
    }

}