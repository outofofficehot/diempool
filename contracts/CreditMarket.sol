// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title CreditMarket
 * @notice A market for buying AI inference credits from the DIEMPool
 * 
 * Features:
 * - Dynamic pricing based on time of day and utilization
 * - Prices decrease as end of day approaches if utilization is low
 * - Credits are tracked on-chain, consumed via API gateway
 * - Unused credits roll over (no daily reset for buyers)
 */
contract CreditMarket is ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;

    // ============================================
    // Constants
    // ============================================

    /// @notice Base price: $0.80 per $1 of credits (20% discount)
    uint256 public constant BASE_PRICE_BPS = 8000; // 80% of face value
    
    /// @notice Minimum price: $0.60 per $1 of credits (40% discount)
    uint256 public constant MIN_PRICE_BPS = 6000; // 60% of face value
    
    /// @notice Maximum price: $0.90 per $1 of credits (10% discount)
    uint256 public constant MAX_PRICE_BPS = 9000; // 90% of face value

    uint256 public constant BPS_DENOMINATOR = 10000;
    
    /// @notice Day duration in seconds
    uint256 public constant DAY_DURATION = 24 hours;

    // ============================================
    // State Variables
    // ============================================

    /// @notice Payment token (e.g., USDC)
    IERC20 public immutable paymentToken;

    /// @notice Reference to the DIEMPool for yield distribution
    address public diemPool;

    /// @notice Total credits available per day (based on staked DIEM)
    uint256 public dailyCreditsCapacity;

    /// @notice Credits consumed today
    uint256 public creditsConsumedToday;

    /// @notice Start of the current day (UTC timestamp)
    uint256 public dayStartTimestamp;

    /// @notice Credit balance per user (in "credit units" = 1e6 per $1)
    mapping(address => uint256) public creditBalance;

    /// @notice Total revenue collected (to be distributed to DIEMPool)
    uint256 public pendingRevenue;

    /// @notice API gateway addresses that can consume credits
    mapping(address => bool) public authorizedGateways;

    // ============================================
    // Events
    // ============================================

    event CreditsPurchased(address indexed buyer, uint256 creditAmount, uint256 paymentAmount, uint256 pricePerCredit);
    event CreditsConsumed(address indexed user, uint256 amount, address indexed gateway);
    event DayReset(uint256 newDayStart, uint256 previousUtilization);
    event CapacityUpdated(uint256 newCapacity);
    event RevenueDistributed(uint256 amount);
    event GatewayAuthorized(address indexed gateway, bool authorized);

    // ============================================
    // Constructor
    // ============================================

    constructor(
        address _paymentToken,
        address _diemPool,
        address _owner
    ) Ownable(_owner) {
        require(_paymentToken != address(0), "Invalid payment token");
        require(_diemPool != address(0), "Invalid DIEM pool");
        
        paymentToken = IERC20(_paymentToken);
        diemPool = _diemPool;
        dayStartTimestamp = _startOfDay(block.timestamp);
    }

    // ============================================
    // Pricing Functions
    // ============================================

    /**
     * @notice Get current price per credit in basis points of face value
     * @return Price in basis points (e.g., 7500 = $0.75 per $1 of credits)
     * 
     * Pricing model:
     * - Starts at BASE_PRICE (80%) at beginning of day
     * - If utilization is high (>80%), price increases toward MAX_PRICE (90%)
     * - If utilization is low, price decreases toward MIN_PRICE (60%) as day ends
     * - Creates incentive to buy credits when underutilized
     */
    function getCurrentPrice() public view returns (uint256) {
        // Check if we need to conceptually reset (actual reset happens on purchase)
        if (block.timestamp >= dayStartTimestamp + DAY_DURATION) {
            // New day - start fresh at base price
            return BASE_PRICE_BPS;
        }

        // Calculate time progress through the day (0 to 10000 bps)
        uint256 timeProgressBps = ((block.timestamp - dayStartTimestamp) * BPS_DENOMINATOR) / DAY_DURATION;
        
        // Calculate current utilization
        uint256 utilizationBps = 0;
        if (dailyCreditsCapacity > 0) {
            utilizationBps = (creditsConsumedToday * BPS_DENOMINATOR) / dailyCreditsCapacity;
        }

        // Dynamic pricing based on utilization and time
        if (utilizationBps >= 8000) {
            // High utilization (>80%) - price goes up
            uint256 priceIncrease = ((utilizationBps - 8000) * (MAX_PRICE_BPS - BASE_PRICE_BPS)) / 2000;
            return BASE_PRICE_BPS + priceIncrease;
        } else {
            // Low utilization - price decreases as day progresses
            // The further into the day with low utilization, the cheaper it gets
            uint256 unusedRatio = BPS_DENOMINATOR - utilizationBps;
            uint256 timeWeight = timeProgressBps; // Later in day = more discount
            
            // Max discount increases with time: starts at 0, ends at (BASE_PRICE - MIN_PRICE)
            uint256 maxDiscount = BASE_PRICE_BPS - MIN_PRICE_BPS; // 2000 bps = 20%
            uint256 discount = (maxDiscount * timeWeight * unusedRatio) / (BPS_DENOMINATOR * BPS_DENOMINATOR);
            
            uint256 price = BASE_PRICE_BPS - discount;
            return price < MIN_PRICE_BPS ? MIN_PRICE_BPS : price;
        }
    }

    /**
     * @notice Get the cost to buy a specific amount of credits
     * @param creditAmount Amount of credits desired (in credit units, 1e6 = $1)
     * @return cost Amount of payment tokens needed
     */
    function getCreditCost(uint256 creditAmount) public view returns (uint256) {
        uint256 priceBps = getCurrentPrice();
        // creditAmount is in 1e6 units, payment token assumed 6 decimals (USDC)
        return (creditAmount * priceBps) / BPS_DENOMINATOR;
    }

    // ============================================
    // Purchase Functions
    // ============================================

    /**
     * @notice Purchase credits with payment tokens
     * @param creditAmount Amount of credits to purchase (1e6 = $1 of inference)
     */
    function buyCredits(uint256 creditAmount) external nonReentrant whenNotPaused {
        require(creditAmount > 0, "Cannot buy 0 credits");
        
        // Reset day if needed
        _checkAndResetDay();

        // Calculate cost at current price
        uint256 price = getCurrentPrice();
        uint256 cost = (creditAmount * price) / BPS_DENOMINATOR;
        require(cost > 0, "Cost too small");

        // Transfer payment
        paymentToken.safeTransferFrom(msg.sender, address(this), cost);

        // Credit the buyer
        creditBalance[msg.sender] += creditAmount;

        // Track revenue
        pendingRevenue += cost;

        emit CreditsPurchased(msg.sender, creditAmount, cost, price);
    }

    /**
     * @notice Buy credits by specifying max payment amount
     * @param maxPayment Maximum payment tokens to spend
     * @return creditAmount Amount of credits received
     */
    function buyCreditsWithMaxPayment(uint256 maxPayment) external nonReentrant whenNotPaused returns (uint256) {
        require(maxPayment > 0, "Cannot pay 0");
        
        _checkAndResetDay();

        uint256 price = getCurrentPrice();
        // Calculate credits: payment * 10000 / price
        uint256 creditAmount = (maxPayment * BPS_DENOMINATOR) / price;
        require(creditAmount > 0, "Payment too small");

        // Transfer payment
        paymentToken.safeTransferFrom(msg.sender, address(this), maxPayment);

        // Credit the buyer
        creditBalance[msg.sender] += creditAmount;

        // Track revenue
        pendingRevenue += maxPayment;

        emit CreditsPurchased(msg.sender, creditAmount, maxPayment, price);
        
        return creditAmount;
    }

    // ============================================
    // Credit Consumption (Gateway Only)
    // ============================================

    /**
     * @notice Consume credits for a user (called by API gateway)
     * @param user User whose credits to consume
     * @param amount Amount of credits to consume
     */
    function consumeCredits(address user, uint256 amount) external nonReentrant {
        require(authorizedGateways[msg.sender], "Not authorized gateway");
        require(creditBalance[user] >= amount, "Insufficient credits");

        creditBalance[user] -= amount;
        creditsConsumedToday += amount;

        emit CreditsConsumed(user, amount, msg.sender);
    }

    // ============================================
    // Admin Functions
    // ============================================

    /**
     * @notice Update daily credit capacity (based on staked DIEM)
     * @param newCapacity New daily capacity in credit units
     */
    function updateCapacity(uint256 newCapacity) external onlyOwner {
        dailyCreditsCapacity = newCapacity;
        emit CapacityUpdated(newCapacity);
    }

    /**
     * @notice Authorize or revoke an API gateway
     */
    function setGatewayAuthorization(address gateway, bool authorized) external onlyOwner {
        authorizedGateways[gateway] = authorized;
        emit GatewayAuthorized(gateway, authorized);
    }

    /**
     * @notice Distribute accumulated revenue to DIEMPool
     */
    function distributeRevenue() external onlyOwner nonReentrant {
        uint256 amount = pendingRevenue;
        require(amount > 0, "No revenue to distribute");
        
        pendingRevenue = 0;
        
        // Approve DIEMPool to pull the tokens
        paymentToken.safeIncreaseAllowance(diemPool, amount);
        
        // Call distributeYield on DIEMPool
        // Note: DIEMPool.distributeYield will transferFrom this contract
        (bool success, ) = diemPool.call(
            abi.encodeWithSignature("distributeYield(uint256)", amount)
        );
        require(success, "Distribution failed");
        
        emit RevenueDistributed(amount);
    }

    /**
     * @notice Update the DIEMPool address
     */
    function setDiemPool(address _diemPool) external onlyOwner {
        require(_diemPool != address(0), "Invalid address");
        diemPool = _diemPool;
    }

    // ============================================
    // View Functions
    // ============================================

    /**
     * @notice Get current utilization rate
     */
    function getUtilization() external view returns (uint256) {
        if (dailyCreditsCapacity == 0) return 0;
        return (creditsConsumedToday * BPS_DENOMINATOR) / dailyCreditsCapacity;
    }

    /**
     * @notice Get time remaining in current pricing day
     */
    function getTimeRemainingInDay() external view returns (uint256) {
        uint256 dayEnd = dayStartTimestamp + DAY_DURATION;
        if (block.timestamp >= dayEnd) return 0;
        return dayEnd - block.timestamp;
    }

    /**
     * @notice Get market statistics
     */
    function getMarketStats() external view returns (
        uint256 _dailyCapacity,
        uint256 _consumedToday,
        uint256 _currentPrice,
        uint256 _pendingRevenue,
        uint256 _utilizationBps
    ) {
        uint256 utilization = 0;
        if (dailyCreditsCapacity > 0) {
            utilization = (creditsConsumedToday * BPS_DENOMINATOR) / dailyCreditsCapacity;
        }
        
        return (
            dailyCreditsCapacity,
            creditsConsumedToday,
            getCurrentPrice(),
            pendingRevenue,
            utilization
        );
    }

    // ============================================
    // Internal Functions
    // ============================================

    /**
     * @notice Check if day has passed and reset counters
     */
    function _checkAndResetDay() internal {
        if (block.timestamp >= dayStartTimestamp + DAY_DURATION) {
            uint256 previousUtilization = 0;
            if (dailyCreditsCapacity > 0) {
                previousUtilization = (creditsConsumedToday * BPS_DENOMINATOR) / dailyCreditsCapacity;
            }
            
            // Reset for new day
            dayStartTimestamp = _startOfDay(block.timestamp);
            creditsConsumedToday = 0;
            
            emit DayReset(dayStartTimestamp, previousUtilization);
        }
    }

    /**
     * @notice Get start of day (00:00 UTC) for a timestamp
     */
    function _startOfDay(uint256 timestamp) internal pure returns (uint256) {
        return (timestamp / DAY_DURATION) * DAY_DURATION;
    }

    // ============================================
    // Emergency Functions
    // ============================================

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Emergency withdraw stuck tokens (not user credits)
     */
    function emergencyWithdrawToken(address token, uint256 amount) external onlyOwner {
        require(token != address(paymentToken) || amount <= pendingRevenue, "Cannot withdraw user funds");
        IERC20(token).safeTransfer(owner(), amount);
    }
}
