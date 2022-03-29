// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MyERC20 is ERC20 {
  constructor () ERC20("My Token", "TKN") {
    _mint(msg.sender, 1_000_000 ether);
  }
}

contract StakingRewards {
    struct Timelock
    {
        uint timestamp;
        uint amount;
    }

    IERC20 public token = IERC20(0xc6fde4a5581Bd55005745FcD8e6C9dC3f46Cfe44);
    uint public rewardRate = 100;
    uint public TIMELOCK = 5 minutes;
    
    uint public lastUpdateTime;
    uint public rewardPerTokenStored;

    mapping(address => uint) public userRewardPerTokenPaid;
    mapping(address => uint) public rewards;

    uint private _totalSupply;
    mapping(address => uint) public _balances;

    mapping(address => mapping(uint => Timelock)) public timelock_stake;
    mapping(address => mapping(uint => Timelock)) public timelock_claims;
    mapping(address => uint) public user_timelock_stake_count;
    mapping(address => uint) public user_timelock_claims_count;

    // HELPERS //

    function rewardPerToken() public view returns (uint) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored +
            (((block.timestamp - lastUpdateTime) * rewardRate * 1e18) / _totalSupply);
    }

    function earned(address account) public view returns (uint) {
        return
            ((_balances[account] *
                (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18) +
            rewards[account];
    }

    function calculateClaim(address _address) public view returns (uint) {
        uint amount_to_claim_temp;
        for(uint i = 0;
            i < user_timelock_claims_count[_address];
            i++)
        {
            if(block.timestamp >= timelock_claims[_address][i].timestamp)
            {
                amount_to_claim_temp += timelock_claims[_address][i].amount;
            } else
            {
                break;
            }
        }
        // Return all claimables if last timelock is completed
        if(user_timelock_claims_count[_address] > 0
            && block.timestamp >= timelock_claims[_address][user_timelock_claims_count[_address]-1].timestamp)
        {
            return earned(msg.sender);
        }
        return amount_to_claim_temp;
    }

    function addressCanWithdraw(address _address, uint _amount) internal returns (bool) {
        uint amount_to_withdraw_temp = _amount;
        for(uint i = 0;
            i < user_timelock_stake_count[_address];
            i++)
        {
            if(block.timestamp >= timelock_stake[_address][i].timestamp)
            {
                if(_amount <= timelock_stake[_address][i].amount)
                {
                    timelock_stake[_address][i].amount -= amount_to_withdraw_temp;
                    amount_to_withdraw_temp = 0;
                } else
                {
                    amount_to_withdraw_temp -= timelock_stake[_address][i].amount;
                    timelock_stake[_address][i].amount = 0;
                }
            } else
            {
                break;
            }
        }
        return amount_to_withdraw_temp == 0;
    }

    function processClaim(address _address) internal returns (uint) {
        uint amount_to_claim_temp;
        for(uint i = 0;
            i < user_timelock_claims_count[_address];
            i++)
        {
            if(block.timestamp >= timelock_claims[_address][i].timestamp)
            {
                amount_to_claim_temp += timelock_claims[_address][i].amount;
                timelock_claims[_address][i].amount = 0;
            } else
            {
                break;
            }
        }
        // Return all claimables if last timelock is completed
        if(user_timelock_claims_count[_address] > 0
            && block.timestamp >= timelock_claims[_address][user_timelock_claims_count[_address]-1].timestamp)
        {
            return rewards[msg.sender];
        }
        return amount_to_claim_temp;
    }

    // MODIFIERS //

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;

        rewards[account] = earned(account);
        userRewardPerTokenPaid[account] = rewardPerTokenStored;
        _;
    }

    // PUBLIC FUNCTIONS //

    function stake(uint _amount) external updateReward(msg.sender) {
        // Timelock code
        timelock_stake[msg.sender][user_timelock_stake_count[msg.sender]]
            = Timelock(block.timestamp + TIMELOCK, _amount);
        user_timelock_stake_count[msg.sender] += 1;


        if(user_timelock_claims_count[msg.sender] > 0)
        {
            timelock_claims[msg.sender][user_timelock_claims_count[msg.sender] - 1].amount = rewards[msg.sender];
        }
        timelock_claims[msg.sender][user_timelock_claims_count[msg.sender]]
            = Timelock(block.timestamp + TIMELOCK, 0);
        user_timelock_claims_count[msg.sender] += 1;
        // end Timelock code

        _totalSupply += _amount;
        _balances[msg.sender] += _amount;
        token.transferFrom(msg.sender, address(this), _amount);
    }

    function withdraw(uint _amount) external updateReward(msg.sender) {
        require(addressCanWithdraw(msg.sender, _amount), "Not enough available funds to withdraw");
        _totalSupply -= _amount;
        _balances[msg.sender] -= _amount;
        token.transfer(msg.sender, _amount);
    }

    function claim() external updateReward(msg.sender) {
        uint claim_amount = processClaim(msg.sender);
        require(claim_amount > 0, "Not available funds to claim");
        rewards[msg.sender] = 0;
        token.transfer(msg.sender, claim_amount);
    }
}
/*
interface IERC20 {
    function totalSupply() external view returns (uint);

    function balanceOf(address account) external view returns (uint);

    function transfer(address recipient, uint amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint amount
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(address indexed owner, address indexed spender, uint value);
}
*/
