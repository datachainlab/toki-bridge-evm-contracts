// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
@title Voting Escrow
@author Curve Finance
@license MIT
@notice Votes have a weight depending on time, so that users are
        committed to the future of (whatever they are voting for)
@dev Vote weight decays linearly over time. Lock time cannot be
     more than `MAXTIME` (3 years).

# Voting escrow to have time-weighted votes
# Votes have a weight depending on time, so that users are committed
# to the future of (whatever they are voting for).
# The weight in this implementation is linear, and lock cannot be more than maxtime:
# w ^
# 1 +        /
#   |      /
#   |    /
#   |  /
#   |/
# 0 +--------+------> time
#       maxtime (3 years?)
*/

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

struct Point {
    int128 bias;
    int128 slope; // # -dweight / dt
    uint256 ts;
    uint256 blk; // block
}
/* We cannot really do block numbers per se b/c slope is per time, not per block
 * and per block could be fairly bad b/c Ethereum changes blocktimes.
 * What we can do is to extrapolate ***At functions */

struct LockedBalance {
    int128 amount;
    uint256 end;
}

contract VotingEscrow is Ownable, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using SafeCast for int256;

    enum DepositType {
        DEPOSIT_FOR_TYPE,
        CREATE_LOCK_TYPE,
        INCREASE_LOCK_AMOUNT,
        INCREASE_UNLOCK_TIME
    }

    uint256 internal constant WEEK = 1 weeks;
    uint256 public constant MAXTIME = 3 * 365 * 86400;
    int128 internal constant IMAXTIME = 3 * 365 * 86400;
    uint256 internal constant MULTIPLIER = 1 ether;

    uint256 public immutable MINTIME;
    address public immutable TOKEN;
    uint256 public supply;
    bool public unlocked;

    mapping(address => LockedBalance) public locked;

    uint256 public epoch;
    mapping(uint256 => Point) public pointHistory; // epoch -> unsigned point
    mapping(address => Point[1000000000]) public userPointHistory; // user -> Point[user_epoch]
    mapping(address => uint256) public userPointEpoch;
    mapping(uint256 => int128) public slopeChanges; // time -> signed slope change

    // Aragon's view methods for compatibility
    address public controller;
    bool public transfersEnabled;

    string public constant NAME = "veTOKI";
    string public constant SYMBOL = "veTOKI";
    string public constant VERSION = "1.0.0";
    uint8 public constant DECIMALS = 18;

    // Whitelisted (smart contract) wallets which are allowed to deposit
    // The goal is to prevent tokenizing the escrow
    mapping(address => bool) public contractsWhitelist;

    event Deposit(
        address indexed provider,
        uint256 value,
        uint256 indexed locktime,
        DepositType depositType,
        uint256 ts
    );

    event Withdraw(address indexed provider, uint256 value, uint256 ts);

    event Supply(uint256 prevSupply, uint256 supply);

    event AddWhitelist(address addr);

    event RemoveWhitelist(address addr);

    event Unlock();

    modifier onlyUserOrWhitelist() {
        if (msg.sender.code.length > 0) {
            require(
                contractsWhitelist[msg.sender],
                "Smart contract not allowed"
            );
        }
        _;
    }

    modifier notUnlocked() {
        require(!unlocked, "unlocked globally");
        _;
    }

    /// @notice Contract constructor
    /// @param token `ERC20TOKI` token address
    constructor(address token, uint256 minTime) Ownable(msg.sender) {
        TOKEN = token;
        MINTIME = minTime;
        pointHistory[0].blk = block.number;
        pointHistory[0].ts = block.timestamp;
        controller = msg.sender;
        transfersEnabled = true;
    }

    // ========================== external functions ===============================
    /// @notice Add address to whitelist smart contract depositors `addr`
    /// @param addr Address to be whitelisted
    function addToWhitelist(address addr) external onlyOwner {
        contractsWhitelist[addr] = true;
        emit AddWhitelist(addr);
    }

    /// @notice Remove a smart contract address from whitelist
    /// @param addr Address to be removed from whitelist
    function removeFromWhitelist(address addr) external onlyOwner {
        contractsWhitelist[addr] = false;
        emit RemoveWhitelist(addr);
    }

    /// @notice Unlock all locked balances
    function unlock() external onlyOwner {
        unlocked = true;
        emit Unlock();
    }

    /// @notice Record global data to checkpoint
    function checkpoint() external notUnlocked {
        _checkpoint(address(0x0), LockedBalance(0, 0), LockedBalance(0, 0));
    }

    /// @notice Deposit `value` tokens for `addr` and add to the lock
    /// @dev Anyone (even a smart contract) can deposit for someone else, but
    ///      cannot extend their locktime and deposit for a brand new user
    /// @param addr User's wallet address
    /// @param value Amount to add to user's lock
    function depositFor(
        address addr,
        uint256 value
    ) external nonReentrant notUnlocked {
        LockedBalance memory locked_ = locked[addr];

        require(value > 0); // dev: need non-zero value
        require(locked_.amount > 0, "No existing lock found");
        require(
            locked_.end > block.timestamp,
            "Cannot add to expired lock. Withdraw"
        );
        _depositFor(addr, value, 0, locked_, DepositType.DEPOSIT_FOR_TYPE);
    }

    /// @notice External function for _createLock
    /// @param value Amount to deposit
    /// @param unlockTime Epoch time when tokens unlock, rounded down to whole weeks
    function createLock(
        uint256 value,
        uint256 unlockTime
    ) external nonReentrant onlyUserOrWhitelist notUnlocked {
        _createLock(value, unlockTime);
    }

    /// @notice Deposit `value` additional tokens for `msg.sender` without modifying the unlock time
    /// @param value Amount of tokens to deposit and add to the lock
    function increaseAmount(
        uint256 value
    ) external nonReentrant onlyUserOrWhitelist notUnlocked {
        _increaseAmount(value);
    }

    /// @notice Extend the unlock time for `msg.sender` to `unlockTime`
    /// @param unlockTime New epoch time for unlocking
    function increaseUnlockTime(
        uint256 unlockTime
    ) external nonReentrant onlyUserOrWhitelist notUnlocked {
        _increaseUnlockTime(unlockTime);
    }

    /// @notice Extend the unlock time and/or for `msg.sender` to `unlockTime`
    /// @param unlockTime New epoch time for unlocking
    function increaseAmountAndTime(
        uint256 value,
        uint256 unlockTime
    ) external nonReentrant onlyUserOrWhitelist notUnlocked {
        require(
            value > 0 || unlockTime > 0,
            "Value and Unlock cannot both be 0"
        );
        if (value > 0 && unlockTime > 0) {
            _increaseAmount(value);
            _increaseUnlockTime(unlockTime);
        } else if (value > 0 && unlockTime == 0) {
            _increaseAmount(value);
        } else {
            _increaseUnlockTime(unlockTime);
        }
    }

    function withdraw() external nonReentrant {
        _withdraw();
    }

    /// @notice Deposit `value` tokens for `msg.sender` and lock until `unlockTime`
    /// @param value Amount to deposit
    /// @param unlockTime Epoch time when tokens unlock, rounded down to whole weeks
    function withdrawAndCreateLock(
        uint256 value,
        uint256 unlockTime
    ) external nonReentrant onlyUserOrWhitelist notUnlocked {
        _withdraw();
        _createLock(value, unlockTime);
    }

    // Dummy methods for compatibility with Aragon
    function changeController(address newController) external {
        require(msg.sender == controller);
        controller = newController;
    }

    /// @notice Get the most recently recorded rate of voting power decrease for `_addr`
    /// @param addr Address of the user wallet
    /// @return Value of the slope
    function getLastUserSlope(address addr) external view returns (int128) {
        uint256 uepoch = userPointEpoch[addr];
        return userPointHistory[addr][uepoch].slope;
    }

    /// @notice Get the timestamp for checkpoint `idx` for `addr`
    /// @param addr User wallet address
    /// @param idx User epoch number
    /// @return Epoch time of the checkpoint
    function userPointHistoryTs(
        address addr,
        uint256 idx
    ) external view returns (uint256) {
        return userPointHistory[addr][idx].ts;
    }

    /// @notice Get timestamp when `addr`'s lock finishes
    /// @param addr User wallet address
    /// @return Epoch time of the lock end
    function lockedEnd(address addr) external view returns (uint256) {
        return locked[addr].end;
    }

    function balanceOfAtT(
        address addr,
        uint256 _t
    ) external view returns (uint256) {
        return _balanceOf(addr, _t);
    }

    function balanceOf(address addr) external view returns (uint256) {
        return _balanceOf(addr, block.timestamp);
    }

    /// @notice Measure voting power of `addr` at block height `block`
    /// @dev Adheres to MiniMe `balanceOfAt` interface: https://github.com/Giveth/minime
    /// @param addr User's wallet address
    /// @param blk Block to calculate the voting power at
    /// @return Voting power
    function balanceOfAt(
        address addr,
        uint256 blk
    ) external view returns (uint256) {
        // Copying and pasting totalSupply code because Vyper cannot pass by
        // reference yet
        require(blk <= block.number);

        // Binary search
        uint256 min = 0;
        uint256 max = userPointEpoch[addr];
        for (uint256 i = 0; i < 128; ++i) {
            // Will be always enough for 128-bit numbers
            if (min >= max) {
                break;
            }
            uint256 mid = (min + max + 1) / 2;
            if (userPointHistory[addr][mid].blk <= blk) {
                min = mid;
            } else {
                max = mid - 1;
            }
        }

        Point memory upoint = userPointHistory[addr][min];

        uint256 maxEpoch = epoch;
        uint256 epoch_ = _findBlockEpoch(blk, maxEpoch);
        Point memory point0 = pointHistory[epoch_];
        uint256 dBlock = 0;
        uint256 dTs = 0;
        if (epoch_ < maxEpoch) {
            Point memory point1 = pointHistory[epoch_ + 1];
            dBlock = point1.blk - point0.blk;
            dTs = point1.ts - point0.ts;
        } else {
            dBlock = block.number - point0.blk;
            dTs = block.timestamp - point0.ts;
        }
        uint256 blockTs = point0.ts;
        if (dBlock != 0) {
            blockTs += (dTs * (blk - point0.blk)) / dBlock;
        }

        upoint.bias -=
            upoint.slope *
            (blockTs - upoint.ts).toInt256().toInt128();
        if (upoint.bias >= 0) {
            return int256(upoint.bias).toUint256();
        } else {
            return 0;
        }
    }

    function totalSupplyAtT(uint256 ts) external view returns (uint256) {
        return _totalSupply(ts);
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply(block.timestamp);
    }

    /// @notice Calculate total voting power at some point in the past
    /// @param blk Block to calculate the total voting power at
    /// @return Total voting power at `blk`
    function totalSupplyAt(uint256 blk) external view returns (uint256) {
        require(blk <= block.number);
        uint256 epoch_ = epoch;
        uint256 targetEpoch = _findBlockEpoch(blk, epoch_);

        /* ========== EVENTS ========== */
        Point memory point = pointHistory[targetEpoch];
        uint256 dt = 0;
        if (targetEpoch < epoch_) {
            Point memory pointNext = pointHistory[targetEpoch + 1];
            if (point.blk != pointNext.blk) {
                dt =
                    ((blk - point.blk) * (pointNext.ts - point.ts)) /
                    (pointNext.blk - point.blk);
            }
        } else {
            if (point.blk != block.number) {
                dt =
                    ((blk - point.blk) * (block.timestamp - point.ts)) /
                    (block.number - point.blk);
            }
        }
        // Now dt contains info on how far are we beyond point
        return _supplyAt(point, point.ts + dt);
    }

    // ========================== internal functions ===============================
    /// @notice Record global and per-user data to checkpoint
    /// @param addr User's wallet address. No user checkpoint if 0x0
    /// @param oldLocked Pevious locked amount / end lock time for the user
    /// @param newLocked New locked amount / end lock time for the user
    function _checkpoint(
        address addr,
        LockedBalance memory oldLocked,
        LockedBalance memory newLocked
    ) internal {
        Point memory uOld;
        Point memory uNew;
        int128 oldDslope = 0;
        int128 newDslope = 0;
        uint256 epoch_ = epoch;

        if (addr != address(0x0)) {
            // Calculate slopes and biases
            // Kept at zero when they have to
            if (oldLocked.end > block.timestamp && oldLocked.amount > 0) {
                uOld.slope = oldLocked.amount / IMAXTIME;
                uOld.bias =
                    uOld.slope *
                    (oldLocked.end - block.timestamp).toInt256().toInt128();
            }
            if (newLocked.end > block.timestamp && newLocked.amount > 0) {
                uNew.slope = newLocked.amount / IMAXTIME;
                uNew.bias =
                    uNew.slope *
                    (newLocked.end - block.timestamp).toInt256().toInt128();
            }

            // Read values of scheduled changes in the slope
            // old_locked.end can be in the past and in the future
            // new_locked.end can ONLY by in the FUTURE unless everything expired: than zeros
            oldDslope = slopeChanges[oldLocked.end];
            if (newLocked.end != 0) {
                if (newLocked.end == oldLocked.end) {
                    newDslope = oldDslope;
                } else {
                    newDslope = slopeChanges[newLocked.end];
                }
            }
        }

        Point memory lastPoint = Point({
            bias: 0,
            slope: 0,
            ts: block.timestamp,
            blk: block.number
        });
        if (epoch_ > 0) {
            lastPoint = pointHistory[epoch_];
        }
        uint256 lastCheckpoint = lastPoint.ts;
        // initial_last_point is used for extrapolation to calculate block number
        // (approximately, for *At methods) and save them
        // as we cannot figure that out exactly from inside the contract

        uint256 initialLastPointTs = lastPoint.ts;
        uint256 initialLastPointBlk = lastPoint.blk;

        uint256 blockSlope = 0; // dblock/dt
        if (block.timestamp > lastPoint.ts) {
            blockSlope =
                (MULTIPLIER * (block.number - lastPoint.blk)) /
                (block.timestamp - lastPoint.ts);
        }
        // If last point is already recorded in this block, slope=0
        // But that's ok b/c we know the block in such case

        // Go over weeks to fill history and calculate what the current point is
        uint256 ti = (lastCheckpoint / WEEK) * WEEK;
        for (uint256 i = 0; i < 255; ++i) {
            // Hopefully it won't happen that this won't get used in 5 years!
            // If it does, users will be able to withdraw but vote weight will be broken
            ti += WEEK;
            int128 dSlope = 0;
            if (ti > block.timestamp) {
                ti = block.timestamp;
            } else {
                dSlope = slopeChanges[ti];
            }
            lastPoint.bias -=
                lastPoint.slope *
                (ti - lastCheckpoint).toInt256().toInt128();
            lastPoint.slope += dSlope;
            if (lastPoint.bias < 0) {
                // This can happen
                lastPoint.bias = 0;
            }
            if (lastPoint.slope < 0) {
                // This cannot happen - just in case
                lastPoint.slope = 0;
            }
            lastCheckpoint = ti;
            lastPoint.ts = ti;
            lastPoint.blk =
                initialLastPointBlk +
                (blockSlope * (ti - initialLastPointTs)) /
                MULTIPLIER;

            epoch_ += 1;
            if (ti == block.timestamp) {
                lastPoint.blk = block.number;
                break;
            } else {
                pointHistory[epoch_] = lastPoint;
            }
        }

        epoch = epoch_;
        // Now point_history is filled until t=now

        if (addr != address(0x0)) {
            // If last point was in this block, the slope change has been applied already
            // But in such case we have 0 slope(s)
            lastPoint.slope += (uNew.slope - uOld.slope);
            lastPoint.bias += (uNew.bias - uOld.bias);
            if (lastPoint.slope < 0) {
                lastPoint.slope = 0;
            }
            if (lastPoint.bias < 0) {
                lastPoint.bias = 0;
            }
        }

        // Record the changed point into history
        pointHistory[epoch_] = lastPoint;

        if (addr != address(0x0)) {
            // Schedule the slope changes (slope is going down)
            // We subtract newUserSlope from [newLocked.end]
            // and add oldUserSlope to [oldLocked.end]
            if (oldLocked.end > block.timestamp) {
                // old_dslope was <something> - uOld.slope, so we cancel that
                oldDslope += uOld.slope;
                if (newLocked.end == oldLocked.end) {
                    oldDslope -= uNew.slope; // It was a new deposit, not extension
                }
                slopeChanges[oldLocked.end] = oldDslope;
            }

            if (newLocked.end > block.timestamp) {
                if (newLocked.end > oldLocked.end) {
                    newDslope -= uNew.slope; // old slope disappeared at this point
                    slopeChanges[newLocked.end] = newDslope;
                }
                // else: we recorded it already in oldDslope
            }
            // Now handle user history
            address _addr = addr;
            uint256 userEpoch = userPointEpoch[_addr] + 1;

            userPointEpoch[_addr] = userEpoch;
            uNew.ts = block.timestamp;
            uNew.blk = block.number;
            userPointHistory[_addr][userEpoch] = uNew;
        }
    }

    /// @notice Deposit and lock tokens for a user
    /// @param addr User's wallet address
    /// @param value Amount to deposit
    /// @param unlockTime New time when to unlock the tokens, or 0 if unchanged
    /// @param lockedBalance Previous locked amount / timestamp
    /// @param depositType The type of deposit
    function _depositFor(
        address addr,
        uint256 value,
        uint256 unlockTime,
        LockedBalance memory lockedBalance,
        DepositType depositType
    ) internal {
        LockedBalance memory locked_ = lockedBalance;
        uint256 supplyBefore = supply;

        supply = supplyBefore + value;
        LockedBalance memory oldLocked;
        (oldLocked.amount, oldLocked.end) = (locked_.amount, locked_.end);
        // Adding to existing lock, or if a lock is expired - creating a new one
        locked_.amount += value.toInt256().toInt128();
        if (unlockTime != 0) {
            locked_.end = unlockTime;
        }
        locked[addr] = locked_;

        // Possibilities:
        // Both old_locked.end could be current or expired (>/< block.timestamp)
        // value == 0 (extend lock) or value > 0 (add to lock or extend lock)
        // locked.end > block.timestamp (always)
        _checkpoint(addr, oldLocked, locked_);

        if (value != 0) {
            IERC20(TOKEN).safeTransferFrom(addr, address(this), value);
        }

        emit Deposit(addr, value, locked_.end, depositType, block.timestamp);
        emit Supply(supplyBefore, supplyBefore + value);
    }

    /// @notice Deposit `_value` tokens for `msg.sender` and lock until `_unlock_time`
    /// @param value Amount to deposit
    /// @param unlockTime Epoch time when tokens unlock, rounded down to whole weeks
    function _createLock(uint256 value, uint256 unlockTime) internal {
        require(value > 0); // dev: need non-zero value

        LockedBalance memory locked_ = locked[msg.sender];
        require(locked_.amount == 0, "Withdraw old tokens first");

        uint256 unlockTimeRounded = (unlockTime / WEEK) * WEEK; // Locktime is rounded down to weeks
        require(
            unlockTimeRounded >= block.timestamp + MINTIME,
            "Voting lock must be at least minTime"
        );
        require(
            unlockTimeRounded <= block.timestamp + MAXTIME,
            "Voting lock can be 3 years max"
        );

        _depositFor(
            msg.sender,
            value,
            unlockTimeRounded,
            locked_,
            DepositType.CREATE_LOCK_TYPE
        );
    }

    function _increaseAmount(uint256 value) internal {
        LockedBalance memory locked_ = locked[msg.sender];

        require(value > 0); // dev: need non-zero value
        require(locked_.amount > 0, "No existing lock found");
        require(
            locked_.end > block.timestamp,
            "Cannot add to expired lock. Withdraw"
        );

        _depositFor(
            msg.sender,
            value,
            0,
            locked_,
            DepositType.INCREASE_LOCK_AMOUNT
        );
    }

    function _increaseUnlockTime(uint256 unlockTime) internal {
        LockedBalance memory locked_ = locked[msg.sender];
        uint256 unlockTimeRounded = (unlockTime / WEEK) * WEEK; // Locktime is rounded down to weeks

        require(locked_.end > block.timestamp, "Lock expired");
        require(locked_.amount > 0, "Nothing is locked");
        require(
            unlockTimeRounded > locked_.end,
            "Can only increase lock duration"
        );
        require(
            unlockTimeRounded <= block.timestamp + MAXTIME,
            "Voting lock can be 3 years max"
        );

        _depositFor(
            msg.sender,
            0,
            unlockTimeRounded,
            locked_,
            DepositType.INCREASE_UNLOCK_TIME
        );
    }

    /// @notice Withdraw all tokens for `msg.sender`
    /// @dev Only possible if the lock has expired
    function _withdraw() internal {
        LockedBalance memory locked_ = locked[msg.sender];
        uint256 value = int256(locked_.amount).toUint256();

        if (!unlocked) {
            require(block.timestamp >= locked_.end, "The lock didn't expire");
        }

        locked[msg.sender] = LockedBalance(0, 0);
        uint256 supplyBefore = supply;
        supply = supplyBefore - value;

        // old_locked can have either expired <= timestamp or zero end
        // locked has only 0 end
        // Both can have >= 0 amount
        _checkpoint(msg.sender, locked_, LockedBalance(0, 0));

        IERC20(TOKEN).safeTransfer(msg.sender, value);

        emit Withdraw(msg.sender, value, block.timestamp);
        emit Supply(supplyBefore, supplyBefore - value);
    }

    // The following ERC20/minime-compatible methods are not real balanceOf and supply!
    // They measure the weights for the purpose of voting, so they don't represent
    // real coins.

    /// @notice Binary search to estimate timestamp for block number
    /// @param blk Block to find
    /// @param maxEpoch Don't go beyond this epoch
    /// @return Approximate timestamp for block
    function _findBlockEpoch(
        uint256 blk,
        uint256 maxEpoch
    ) internal view returns (uint256) {
        // Binary search
        uint256 min = 0;
        uint256 max = maxEpoch;
        for (uint256 i = 0; i < 128; ++i) {
            // Will be always enough for 128-bit numbers
            if (min >= max) {
                break;
            }
            uint256 mid = (min + max + 1) / 2;
            if (pointHistory[mid].blk <= blk) {
                min = mid;
            } else {
                max = mid - 1;
            }
        }
        return min;
    }

    /// @notice Get the current voting power for `msg.sender`
    /// @dev Adheres to the ERC20 `balanceOf` interface for Aragon compatibility
    /// @param addr User wallet address
    /// @param epochTs Epoch time to return voting power at
    /// @return User voting power
    function _balanceOf(
        address addr,
        uint256 epochTs
    ) internal view returns (uint256) {
        uint256 epoch_ = userPointEpoch[addr];
        if (epoch_ == 0) {
            return 0;
        } else {
            Point memory lastPoint = userPointHistory[addr][epoch_];
            lastPoint.bias -=
                lastPoint.slope *
                (epochTs - lastPoint.ts).toInt256().toInt128();
            if (lastPoint.bias < 0) {
                lastPoint.bias = 0;
            }
            return int256(lastPoint.bias).toUint256();
        }
    }

    /// @notice Calculate total voting power at some point in the past
    /// @param point The point (bias/slope) to start search from
    /// @param ts Time to calculate the total voting power at
    /// @return Total voting power at that time
    function _supplyAt(
        Point memory point,
        uint256 ts
    ) internal view returns (uint256) {
        Point memory lastPoint = point;
        uint256 ti = (lastPoint.ts / WEEK) * WEEK;
        for (uint256 i = 0; i < 255; ++i) {
            ti += WEEK;
            int128 dSlope = 0;
            if (ti > ts) {
                ti = ts;
            } else {
                dSlope = slopeChanges[ti];
            }
            lastPoint.bias -=
                lastPoint.slope *
                (ti - lastPoint.ts).toInt256().toInt128();
            if (ti == ts) {
                break;
            }
            lastPoint.slope += dSlope;
            lastPoint.ts = ti;
        }

        if (lastPoint.bias < 0) {
            lastPoint.bias = 0;
        }
        return int256(lastPoint.bias).toUint256();
    }

    /// @notice Calculate total voting power
    /// @dev Adheres to the ERC20 `totalSupply` interface for Aragon compatibility
    /// @return Total voting power
    function _totalSupply(uint256 ts) internal view returns (uint256) {
        uint256 epoch_ = epoch;
        Point memory lastPoint = pointHistory[epoch_];
        return _supplyAt(lastPoint, ts);
    }
}
