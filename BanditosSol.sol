pragma solidity ^0.4.23;

contract Owned {
    //setup and transfer ownership 
    constructor() public {
        owner = msg.sender;
    }
    //sets modifier to allow function with owner rights
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }
    
    //variables to transfer ownership
    address public owner;
    address public newOwner;
    
    //changing ownership if new owner are set 
    function changeOwner(address _newOwner) public onlyOwner {
        newOwner = _newOwner;
    }

    //accept ownership for a new owner
    function acceptOwnership() public {
        require(msg.sender == newOwner, "should be newOwner to accept");
        owner = newOwner;
    }
}

/**
 * @title SafeMath
 * @dev Math operations with safety checks that revert on error
 */
library SafeMath {

    /**
     * @dev Multiplies two numbers, reverts on overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-solidity/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b);

        return c;
    }

    /**
     * @dev Integer division of two numbers truncating the quotient, reverts on division by zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0); // Solidity only automatically asserts when dividing by 0
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    /**
     * @dev Subtracts two numbers, reverts on overflow (i.e. if subtrahend is greater than minuend).
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a);
        uint256 c = a - b;

        return c;
    }

    /**
     * @dev Adds two numbers, reverts on overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a);

        return c;
    }

    /**
     * @dev Divides two numbers and returns the remainder (unsigned integer modulo),
     * reverts when dividing by zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0);
        return a % b;
    }
}

contract Balances is Owned {
    using SafeMath for uint256;

    uint public constant REP_AND_CASH_DECIMALS = 6; // BANDITS will give round rep/cash, but we could buy even on 0.00001 eth

    uint public constant AIRDROP_COLLECT_TIME_PAUSE = 8 hours;  
    uint public constant USUAL_COLLECT_TIME_PAUSE =  1 hours;
    uint public constant BANDITS_PROFITS_DIVIDED = 30 * 24  hours;  //monthly 

    uint public constant BANDITS_TYPES = 7; //zero type - airdrop - moved to separate
    uint public constant BANDITS_LEVELS = 6;//bandit levels
    uint public constant WANTEDLVL = 10; //wanted levels

    uint public REP_PER_ETH = 50;  //quantity reputation per 1 ether
    uint public CASH_FOR_ETH = 50; //quantity cash per 1 ether

    //safety purposes
    uint256 public MaxEthOnContract = 0;
    uint256 public MaxEthOnContract75 = 0;
    bool public CriticalEthBalance = false;

    //admin and referral percentage
    uint256 constant public ADMIN_PERCENT = 10;
    uint256 constant public REF_PERCENT = 10;

    
    struct RepCount {
        bool unlocked;
        uint256 totalBANDITS;
        uint256 unlockedTime;
    }

    struct PlayerRef {
        address referral;
        uint256 cash;
        uint256 points;
    }

    //player's data, unique per player
    struct PlayerBalance {
        uint256 rep;
        uint256 cash;
        uint256 points;
        uint64 collectedwantedLvl;
        uint64 level;
        bool isganstaUnlocked;

        address referer;
        uint256 refererIndex;

        uint256 referralsCount;
        PlayerRef[] referralsArray;

        uint256 airdropUnlockedTime;
        uint256 airdropCollectedTime;

        uint256 BANDITSCollectedTime;
        uint256 BANDITSTotalPower;
        RepCount[BANDITS_TYPES] RepCountes;

    }
    
    //sets data to array
    mapping(address => PlayerBalance) public playerBalances;

    uint256 public balanceForAdmin = 0;
    
    //statictics
    uint256 public statTotalInvested = 0;
    uint256 public statTotalSold = 0;
    uint256 public statTotalPlayers = 0;
    uint256 public statTotalBANDITS = 0;
    uint256 public statMaxReferralsCount = 0;
    address public statMaxReferralsReferer;

    address[] public statPlayers;

    //incoming transaction function starts inside function
    function () external payable {
        buyrep();
    }

    //function, working with incoming eth
    function buyrep() payable public returns (bool success) {
        require(msg.value > 0, "please pay something");
        uint256 _rep = msg.value;
        _rep = _rep.mul(REP_PER_ETH);

        uint256 _payment = msg.value.mul(ADMIN_PERCENT).div(100);
        balanceForAdmin = (balanceForAdmin.add(_payment));

        PlayerBalance storage player = playerBalances[msg.sender];
        PlayerBalance storage referer = playerBalances[player.referer];

        player.rep = (player.rep.add(_rep));
        player.points = (player.points.add(_rep));
        if (player.collectedwantedLvl < 1) {
            player.collectedwantedLvl = 1;
        }
        if (player.referer != address(0)) {
            uint256 _ref = _rep.mul(REF_PERCENT).div(100);
            referer.points = (referer.points.add(_rep));
            referer.cash = (referer.cash.add(_ref));
            uint256 _index = player.refererIndex;
            referer.referralsArray[_index].cash = (referer.referralsArray[_index].cash.add(_ref));
        }
        if (MaxEthOnContract <= address(this).balance) {
            MaxEthOnContract = address(this).balance;
            MaxEthOnContract75 = MaxEthOnContract.mul(75);
            MaxEthOnContract75 = MaxEthOnContract75.div(100);
            CriticalEthBalance = false;
        }
        statTotalInvested = (statTotalInvested.add(msg.value));

        return true;
    }
    
    //internal func to work with reputation
    function _payrep(uint256 _rep) internal {
        uint256 rep = _rep;
        PlayerBalance storage player = playerBalances[msg.sender];
        if (player.rep < _rep) {
            uint256 cash = _rep.sub(player.rep);
            _paycash(cash);
            rep = player.rep;
        }
        if (rep > 0) {
            player.rep = player.rep.sub(rep);
        }
    }

    //internal func to work with cash
    function _paycash(uint256 _cash) internal {
        PlayerBalance storage player = playerBalances[msg.sender];

        player.cash = player.cash.sub(_cash);
    }
    
    //admin payout
    function withdrawBalance(uint256 _value) external onlyOwner {
        balanceForAdmin = (balanceForAdmin.sub(_value));
        statTotalSold = (statTotalSold.add(_value));
        address(msg.sender).transfer(_value);
    }
}

contract Game is Balances {

    //percentage payout to types
    uint32[BANDITS_TYPES] public BANDITS_PRICES = [100, 500, 1500, 2500, 5000, 10000, 3000];

    uint32[BANDITS_TYPES] public BANDITS_PROFITS_PERCENTS = [100, 102, 105, 110, 115, 120, 130];

    uint32[BANDITS_LEVELS] public BANDITS_LEVELS_cash_PERCENTS = [40, 42, 44, 46, 48, 50];
    uint32[BANDITS_LEVELS] public BANDITS_LEVELS_PRICES = [0, 31500, 95000, 235000, 475000, 785000];

    uint32[BANDITS_TYPES] public BANDITS_TYPES_PRICES = [0, 250, 1000, 2500, 7500, 22500, 0];

    uint32[WANTEDLVL + 1] public WANTEDLVL_POINTS = [0, 100, 250, 500, 1250, 2750, 3750, 4750, 5750, 16000];
    uint32[WANTEDLVL + 1] public WANTEDLVL_REWARD = [0, 1000, 3750, 10000, 27000, 65000, 115000, 175000, 255000, 500000];

    //transfer cash for eth
    function sellcash(uint256 _cash) public returns (bool success) {
        require(_cash > 0, "couldnt sell zero");
        require(_collectAll(), "problems with collect all before unlock bandit");
        PlayerBalance storage player = playerBalances[msg.sender];
        uint256 money = _cash.div(CASH_FOR_ETH);
        require(address(this).balance >= money, "couldnt sell more than total balance");
        player.cash = ( player.cash.sub(_cash));
        address(msg.sender).transfer(money);
        statTotalSold = (statTotalSold.add(money));
        if (address(this).balance < MaxEthOnContract75)  {
            CriticalEthBalance = true;
        }
        return true;
    }
    
    //collect wanted for player 
    function collectwantedLvl() public returns (bool success) {
        PlayerBalance storage player = playerBalances[msg.sender];
        uint64 wantedLvl = player.collectedwantedLvl;
        require(wantedLvl < WANTEDLVL, "no WANTEDLVL left");
        uint256 pointToHave = WANTEDLVL_POINTS[wantedLvl];
        pointToHave = pointToHave.mul(1000000);
        require(player.points >= pointToHave, "not enough points");
        uint256 _rep = WANTEDLVL_REWARD[wantedLvl];
        if (_rep > 0) {
            _rep = _rep.mul(10 ** REP_AND_CASH_DECIMALS);
            player.rep = player.rep.add(_rep);
        }
        player.collectedwantedLvl = wantedLvl + 1;
        return true;
    }

    //adds an airdrop unit
    function unlockAirdropBANDITS(address _referer) public returns (bool success) {
        PlayerBalance storage player = playerBalances[msg.sender];
        require(player.airdropUnlockedTime == 0, "coulnt unlock already unlocked");

        if (playerBalances[_referer].airdropUnlockedTime > 0 || _referer == address(0xC99B66E5Cb46A05Ea997B0847a1ec50Df7fe8976)) {
            player.referer = _referer;
            require(playerBalances[_referer].referralsCount + 1 > playerBalances[_referer].referralsCount, "no overflow");
            playerBalances[_referer].referralsArray.push(PlayerRef(msg.sender, 0, 0));
            player.refererIndex =  playerBalances[_referer].referralsCount;
            playerBalances[_referer].referralsCount++;
            if (playerBalances[_referer].referralsCount > statMaxReferralsCount) {
                statMaxReferralsCount = playerBalances[_referer].referralsCount;
                statMaxReferralsReferer = msg.sender;
            }
        }

        player.airdropUnlockedTime = now;
        player.airdropCollectedTime = now;
        player.RepCountes[0].unlocked = true;
        player.RepCountes[0].unlockedTime = now;
        player.RepCountes[0].totalBANDITS = 0;
        player.BANDITSTotalPower = 0;
        player.collectedwantedLvl = 1;
        player.BANDITSCollectedTime = now;

        statTotalPlayers = (statTotalPlayers.add(1));
        statPlayers.push(msg.sender);
        return true;
    }

    //unlock new type of unit
    function unlocktype(uint _type) public returns (bool success) {
        require(_type > 0, "coulnt unlock already unlocked");
        require(_type < 6, "coulnt unlock out of range");

        PlayerBalance storage player = playerBalances[msg.sender];
        require(!player.RepCountes[_type].unlocked, "coulnt unlock already unlocked");
        if (_type == 5) {
            require(player.collectedwantedLvl >= 9, "platinum wantedLvl required");
        }
        require(_collectAll(), "problems with collect all before unlock bandit");
        uint256 _rep = BANDITS_TYPES_PRICES[_type];
        _rep = _rep.mul(10 ** REP_AND_CASH_DECIMALS);
        _payrep(_rep);
        player.RepCountes[_type].unlocked = true;
        player.RepCountes[_type].unlockedTime = now;
        player.RepCountes[_type].totalBANDITS = 1;
        player.BANDITSTotalPower = (player.BANDITSTotalPower.add(_getBanditPower(_type)));
        statTotalBANDITS = (statTotalBANDITS.add(1));
        return true;
    }

    //buy a bandit with proper type when called
    function buyBandit(uint _type) public returns (bool success) {
        PlayerBalance storage player = playerBalances[msg.sender];
        if (_type == 6) {
            require(CriticalEthBalance, "only when critical eth flag is on");
        } else {
            require(player.RepCountes[_type].unlocked, "coulnt buy in locked bandits");
        }
        require(_collectAll(), "problems with collect all before buy");
        uint256 _rep = BANDITS_PRICES[_type];
        _rep = _rep.mul(10 ** REP_AND_CASH_DECIMALS);
        _payrep(_rep);
        player.RepCountes[_type].totalBANDITS++;
        player.BANDITSTotalPower = (player.BANDITSTotalPower.add(_getBanditPower(_type)));
        statTotalBANDITS = (statTotalBANDITS.add(1));
        return true;
    }

    //buy level when called
    function buyLevel() public returns (bool success) {
        require(_collectAll(), "problems with collect all before level up");
        PlayerBalance storage player = playerBalances[msg.sender];
        uint64 level = player.level + 1;
        require(level < BANDITS_LEVELS, "couldnt go level more than maximum");
        uint256 _cash = BANDITS_LEVELS_PRICES[level];
        _cash = _cash.mul(10 ** REP_AND_CASH_DECIMALS);
        _paycash(_cash);
        player.level = level;
        return true;
    }

    //collect airdrop reputation
    function collectAirdrop() public returns (bool success) {
        PlayerBalance storage player = playerBalances[msg.sender];
        require(player.airdropUnlockedTime > 0, "should be unlocked");
        require(now - player.airdropUnlockedTime >= AIRDROP_COLLECT_TIME_PAUSE, "should be unlocked");
        require(player.airdropCollectedTime == 0 || now - player.airdropCollectedTime >= AIRDROP_COLLECT_TIME_PAUSE, "should be never collected before or more then 8 hours from last collect");
        uint256 _rep = (10 ** REP_AND_CASH_DECIMALS).mul(100);
        player.airdropCollectedTime = now;
        player.rep = (player.rep.add(_rep));
        return true;
    }

    //collects bandits profit
    function collectProducts() public returns (bool success) {
        PlayerBalance storage player = playerBalances[msg.sender];
        uint256 passTime = now - player.BANDITSCollectedTime;
        require(passTime >= USUAL_COLLECT_TIME_PAUSE, "should wait a little bit");
        return _collectAll();
    }

    //info function for a bandits types
    function _getBanditPower(uint _type) public view returns (uint) {
        return BANDITS_PROFITS_PERCENTS[_type] * BANDITS_PRICES[_type];

    }

    //obv. collects all available profit
    function _getCollectAllAvailable() public view returns (uint, uint) {
        PlayerBalance storage player = playerBalances[msg.sender];

        uint256 monthlyIncome = player.BANDITSTotalPower.div(100).mul(10 ** REP_AND_CASH_DECIMALS);
        uint256 passedTime = now.sub(player.BANDITSCollectedTime);
        uint256 income = monthlyIncome.mul(passedTime).div(BANDITS_PROFITS_DIVIDED);

        uint256 _cash = income.mul(BANDITS_LEVELS_cash_PERCENTS[player.level]).div(100);
        uint256 _rep = income.sub(_cash);

        return (_cash, _rep);
    }

    //internal func for working with raw data
    function _collectAll() internal returns (bool success) {
        PlayerBalance storage player = playerBalances[msg.sender];
        uint256 _cash;
        uint256 _rep;
        (_cash, _rep) = _getCollectAllAvailable();
        if (_rep > 0 || _cash > 0) {
            player.BANDITSCollectedTime = now;
        }
        if (_rep > 0) {
            player.rep = player.rep.add(_rep);
        }
        if (_cash > 0) {
            player.cash = player.cash.add(_cash);
        }
        return true;
    }
}

contract CryptoCangs is Game {

    //statictic across the whole game
    function getGameStats() public view returns (uint[], address) {
        uint[] memory combined = new uint[](5);
        combined[0] = statTotalInvested;
        combined[1] = statTotalSold;
        combined[2] = statTotalPlayers;
        combined[3] = statTotalBANDITS;
        combined[4] = statMaxReferralsCount;
        return (combined, statMaxReferralsReferer);
    }

    //stats across player Rep 
    function getRepCountFullInfo(uint _type) public view returns (uint[]) {
        uint[] memory combined = new uint[](5);

        PlayerBalance storage player = playerBalances[msg.sender];

        combined[0] = player.RepCountes[_type].unlocked ? 1 : 0;
        combined[1] = player.RepCountes[_type].totalBANDITS;
        combined[2] = player.RepCountes[_type].unlockedTime;
        combined[3] = player.BANDITSTotalPower;
        combined[4] = player.BANDITSCollectedTime;
        if (_type == 6) {
          combined[0] = CriticalEthBalance ? 1 : 0;
        }
        return combined;
    }

    //players total power
    function getPlayersInfo() public view returns (address[], uint[]) {
        address[] memory combinedA = new address[](statTotalPlayers);
        uint[] memory combinedB = new uint[](statTotalPlayers);
        for (uint i=0; i<statTotalPlayers; i++) {
            combinedA[i] = statPlayers[i];
            combinedB[i] = playerBalances[statPlayers[i]].BANDITSTotalPower;
        }
        return (combinedA, combinedB);
    }

    //stats across all refs
    function getReferralsInfo() public view returns (address[], uint[]) {
        PlayerBalance storage player = playerBalances[msg.sender];

        address[] memory combinedA = new address[](player.referralsCount);
        uint[] memory combinedB = new uint[](player.referralsCount);
        for (uint i=0; i<player.referralsCount; i++) {
            combinedA[i] = player.referralsArray[i].referral;
            combinedB[i] = player.referralsArray[i].cash;
        }
        return (combinedA, combinedB);
    }

    //all players refs count
    function getReferralsNumber(address _address) public view returns (uint) {
        return playerBalances[_address].referralsCount;
    }

    //array with refs addresses
    function getReferralsNumbersList(address[] _addresses) public view returns (uint[]) {
        uint[] memory counters = new uint[](_addresses.length);
        for (uint i = 0; i < _addresses.length; i++) {
            counters[i] = playerBalances[_addresses[i]].referralsCount;
        }

        return counters;
    }

    //shows contract balance
    function getContractBalance() public view returns (uint) {
        return address(this).balance;
    }

    //players rep info
    function playerUnlockedInfo(address _referer) public view returns (uint) {
        return playerBalances[_referer].RepCountes[0].unlocked ? 1 : 0;
    }

    //stats about wanted from player
    function collectwantedLvlInfo() public view returns (uint[]) {
        PlayerBalance storage player = playerBalances[msg.sender];

        uint[] memory combined = new uint[](5);
        uint64 wantedLvl = player.collectedwantedLvl;
        if (wantedLvl >= WANTEDLVL) {
            combined[0] = 1;
            combined[1] = wantedLvl + 1;
            return combined;
        }

        combined[1] = wantedLvl + 1;
        combined[2] = player.points;
        uint256 pointToHave = WANTEDLVL_POINTS[wantedLvl];
        combined[3] = pointToHave.mul(1000000);
        combined[4] = WANTEDLVL_REWARD[wantedLvl];
        combined[4] = combined[4].mul(1000000);

        if (player.points < combined[3]) {
            combined[0] = 2;
            return combined;
        }
        return combined;
    }

    //
    function unlockTypeInfo(uint _type) public view returns (uint[]) {
        PlayerBalance storage player = playerBalances[msg.sender];
        uint[] memory combined = new uint[](4);
        if (_type == 6) {
            if (!CriticalEthBalance) {
                combined[0] = 88;
                return combined;
            }
        } else {
            if (player.RepCountes[_type].unlocked) {
                combined[0] = 2;
                return combined;
            }
            if (_type == 5) {
                if (player.collectedwantedLvl < 9) {
                    combined[0] = 77;
                    return combined;
                }
            }
        }
        uint256 _rep = BANDITS_TYPES_PRICES[_type];
        _rep = _rep.mul(10 ** REP_AND_CASH_DECIMALS);
        uint256 _new_cash;
        uint256 _new_rep;
        (_new_cash, _new_rep) = _getCollectAllAvailable();
        combined[1] = _rep;
        combined[2] = _rep;
        if (player.rep + _new_rep < _rep) {
            combined[2] = player.rep + _new_rep;
            combined[3] = _rep - combined[2];
            if (player.cash + _new_cash < combined[3]) {
                combined[0] = 55;
            }
        }
        return combined;
    }

    //info about bandit 
    function buyBanditInfo(uint _type) public view returns (uint[]) {
        PlayerBalance storage player = playerBalances[msg.sender];
        uint[] memory combined = new uint[](4);
        if (_type == 6) {
            if (!CriticalEthBalance) {
                combined[0] = 88;
                return combined;
            }
        } else {
            if (!player.RepCountes[_type].unlocked) {
                combined[0] = 1;
                return combined;
            }
        }
        uint256 _rep = BANDITS_PRICES[_type];
        _rep = _rep.mul(10 ** REP_AND_CASH_DECIMALS);
        uint256 _new_cash;
        uint256 _new_rep;
        (_new_cash, _new_rep) = _getCollectAllAvailable();
        combined[1] = _rep;
        combined[2] = _rep;
        if (player.rep + _new_rep < _rep) {
            combined[2] = player.rep + _new_rep;
            combined[3] = _rep - combined[2];
            if (player.cash + _new_cash < combined[3]) {
                combined[0] = 55;
            }
        }
        return combined;
    }


    function buyLevelInfo() public view returns (uint[]) {
        PlayerBalance storage player = playerBalances[msg.sender];
        uint[] memory combined = new uint[](4);
        if (player.level + 1 >= BANDITS_LEVELS) {
            combined[0] = 2;
            return combined;
        }
        combined[1] = player.level + 1;
        uint256 _cash = BANDITS_LEVELS_PRICES[combined[1]];
        _cash = _cash.mul(10 ** REP_AND_CASH_DECIMALS);
        combined[2] = _cash;

        uint256 _new_cash;
        uint256 _new_rep;
        (_new_cash, _new_rep) = _getCollectAllAvailable();
        if (player.cash + _new_cash < _cash) {
            combined[0] = 55;
        }

        return combined;
    }


    function collectAirdropInfo() public view returns (uint[]) {
        PlayerBalance storage player = playerBalances[msg.sender];
        uint[] memory combined = new uint[](3);
        if (player.airdropUnlockedTime == 0) {
            combined[0] = 1;
            return combined;
        }
        if (player.airdropUnlockedTime == 0) {
            combined[0] = 2;
            return combined;
        }
        if (now - player.airdropUnlockedTime < AIRDROP_COLLECT_TIME_PAUSE) {
            combined[0] = 10;
            combined[1] = now - player.airdropUnlockedTime;
            combined[2] = AIRDROP_COLLECT_TIME_PAUSE - combined[1];
            return combined;
        }
        if (player.airdropCollectedTime != 0 && now - player.airdropCollectedTime < AIRDROP_COLLECT_TIME_PAUSE) {
            combined[0] = 11;
            combined[1] = now - player.airdropCollectedTime;
            combined[2] = AIRDROP_COLLECT_TIME_PAUSE - combined[1];
            return combined;
        }
        uint256 _rep = (10 ** REP_AND_CASH_DECIMALS).mul(100);
        combined[0] = 0;
        combined[1] = _rep;
        combined[2] = 0;
        if (player.rep + _rep < player.rep) {
            combined[0] = 255;
            return combined;
        }
        return combined;

    }
    
    //info about all profits
    function collectProductsInfo() public view returns (uint[]) {
        PlayerBalance storage player = playerBalances[msg.sender];
        uint[] memory combined = new uint[](3);
        if (!(player.BANDITSCollectedTime > 0)) {
            combined[0] = 3;
            return combined;
        }

        uint256 passTime = now - player.BANDITSCollectedTime;
        if (passTime < USUAL_COLLECT_TIME_PAUSE) {
            combined[0] = 11;
            combined[1] = passTime;
            combined[2] = USUAL_COLLECT_TIME_PAUSE - combined[1];
            return combined;
        }

        uint256 _cash;
        uint256 _rep;
        (_cash, _rep) = _getCollectAllAvailable();

        combined[0] = 0;
        combined[1] = _rep;
        combined[2] = _cash;
        if (player.rep + _rep < player.rep) {
            combined[0] = 255;
            return combined;
        }
        return combined;
    }
}