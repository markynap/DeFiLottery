


contract LotteryTicket {

    // Winner Information
    struct Guess {
        uint256 numberChosen;
        uint256 numberPlacement;
        uint256 numberOfGuesses;
        address[] callers;
    }
    // Number -> NumberPlacementArray
    mapping ( uint256 => Guess[10]) guesses;

}