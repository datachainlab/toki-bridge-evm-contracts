// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import "./interfaces/IFarming.sol";

// https://docs.synthetix.io/contracts/source/contracts/farmingrewards
contract Farming is
    IFarming,
    ReentrancyGuardTransient,
    Pausable,
    AccessControl
{
    using SafeERC20 for IERC20;

    bytes32 public constant REWARD_NOTIFIER = keccak256("REWARD_NOTIFIER");

    /* ========== STATE VARIABLES ========== */

    IERC20 public immutable REWARD_TOKEN;
    mapping(address => uint256) public rewardRate;
    mapping(address => uint256) public lastUpdateTime;
    mapping(address => uint256) public rewardPerTokenStored;

    // Farming token => user => rewardPerTokenPaid
    mapping(address => mapping(address => uint256))
        public userRewardPerTokenPaid;

    // Farming token => user => rewards
    mapping(address => mapping(address => uint256)) public rewards;

    // Farming token => totalSupply
    mapping(address => uint256) public totalSupply;

    // Farming token => user => balance
    mapping(address => mapping(address => uint256)) public balanceOf;

    /* ========== CONSTRUCTOR ========== */

    constructor(address admin, address rewardSetter, address rewardsToken_) {
        REWARD_TOKEN = IERC20(rewardsToken_);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(REWARD_NOTIFIER, rewardSetter);
    }

    /* ========== VIEWS ========== */

    function rewardPerToken(
        address farmingToken
    ) public view returns (uint256) {
        if (totalSupply[farmingToken] == 0) {
            return rewardPerTokenStored[farmingToken];
        }
        return
            rewardPerTokenStored[farmingToken] +
            ((block.timestamp - lastUpdateTime[farmingToken]) *
                rewardRate[farmingToken] *
                1e18) /
            totalSupply[farmingToken];
    }

    function earned(
        address farmingToken,
        address account
    ) public view returns (uint256) {
        return
            (balanceOf[farmingToken][account] *
                (rewardPerToken(farmingToken) -
                    (userRewardPerTokenPaid[farmingToken][account]))) /
            (1e18) +
            (rewards[farmingToken][account]);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */
    // solhint-disable-next-line ordering
    function stake(
        address farmingToken,
        uint256 amount
    )
        external
        nonReentrant
        whenNotPaused
        updateReward(farmingToken, msg.sender)
    {
        require(
            farmingToken != address(REWARD_TOKEN),
            "Cannot stake rewards token"
        );
        require(amount > 0, "Cannot stake 0");
        totalSupply[farmingToken] = totalSupply[farmingToken] + (amount);
        balanceOf[farmingToken][msg.sender] =
            balanceOf[farmingToken][msg.sender] +
            (amount);
        IERC20(farmingToken).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
        emit Stake(farmingToken, msg.sender, amount);
    }

    function withdraw(
        address farmingToken,
        uint256 amount
    ) public nonReentrant updateReward(farmingToken, msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        totalSupply[farmingToken] = totalSupply[farmingToken] - (amount);
        balanceOf[farmingToken][msg.sender] =
            balanceOf[farmingToken][msg.sender] -
            (amount);
        IERC20(farmingToken).safeTransfer(msg.sender, amount);
        emit Withdraw(farmingToken, msg.sender, amount);
    }

    function claimReward(
        address farmingToken
    ) public nonReentrant updateReward(farmingToken, msg.sender) {
        uint256 reward = rewards[farmingToken][msg.sender];
        if (reward > 0) {
            rewards[farmingToken][msg.sender] = 0;
            REWARD_TOKEN.safeTransfer(msg.sender, reward);
            emit PayReward(farmingToken, msg.sender, reward);
        }
    }

    function exit(address farmingToken) external {
        withdraw(farmingToken, balanceOf[farmingToken][msg.sender]);
        claimReward(farmingToken);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function notifyRewardRate(
        address farmingToken,
        uint256 _rewardRate
    )
        external
        onlyRole(REWARD_NOTIFIER)
        updateReward(farmingToken, address(0))
    {
        rewardRate[farmingToken] = _rewardRate;
        emit NotifyRewardRate(farmingToken, _rewardRate);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /* ========== MODIFIERS ========== */

    modifier updateReward(address farmingToken, address account) {
        rewardPerTokenStored[farmingToken] = rewardPerToken(farmingToken);
        lastUpdateTime[farmingToken] = block.timestamp;
        if (account != address(0)) {
            rewards[farmingToken][account] = earned(farmingToken, account);
            userRewardPerTokenPaid[farmingToken][
                account
            ] = rewardPerTokenStored[farmingToken];
        }
        _;
    }

    /* ========== EVENTS ========== */

    event NotifyRewardRate(address indexed farmingToken, uint256 reward);
    event Stake(
        address indexed farmingToken,
        address indexed user,
        uint256 amount
    );
    event Withdraw(
        address indexed farmingToken,
        address indexed user,
        uint256 amount
    );
    event PayReward(
        address indexed farmingToken,
        address indexed user,
        uint256 reward
    );
}
