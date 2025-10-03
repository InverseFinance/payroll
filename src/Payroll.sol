pragma solidity 0.8.13;

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
}

// WARNING: THIS CONTRACT IS NOT COMPATIBLE WITH NON-STANDARD ERC20 TOKENS (e.g. USDT)
contract Payroll {

    mapping(address => Recipient) public recipients;
    mapping(address => uint256) public unclaimed;

    address public immutable treasuryAddress;
    address public immutable governance;
    IERC20 public immutable asset;
    
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    struct Recipient {
        uint256 lastClaim;
        uint256 ratePerSecond;
        uint256 endTime;
    }

    event SetRecipient(address recipient, uint256 amount, uint256 endTime);
    event AmountWithdrawn(address recipient, uint256 amount);

    constructor(address _treasuryAddress, address _governance, address _asset) {
        require(IERC20(_asset).decimals() == 18, "Payroll::constructor: asset must have 18 decimals");
        treasuryAddress = _treasuryAddress;
        governance = _governance;
        asset = IERC20(_asset);
    }

    function balanceOf(address _recipient) public view returns (uint256 bal) {
        bal = unclaimed[_recipient];
        Recipient memory recipient = recipients[_recipient];
        uint256 accrualEnd = block.timestamp < recipient.endTime ? block.timestamp : recipient.endTime;
        uint256 accrualStart = recipient.lastClaim < accrualEnd ? recipient.lastClaim : accrualEnd;
        bal += recipient.ratePerSecond * (accrualEnd - accrualStart);
    }

    function updateRecipient(address recipient) internal {
        unclaimed[recipient] = balanceOf(recipient);
        recipients[recipient].lastClaim = block.timestamp;
    }

    function setRecipient(address _recipient, uint256 _yearlyAmount, uint256 _endTime) external {
        updateRecipient(_recipient);
        require(msg.sender == governance, "Payroll::setRecipient: only governance");
        require(_recipient != address(0), "Payroll::setRecipient: zero address!");

        // endTime cannot be in the past
        if(_endTime < block.timestamp) {
            _endTime = block.timestamp;
        }

        recipients[_recipient] = Recipient({
            lastClaim: block.timestamp,
            ratePerSecond: _yearlyAmount / SECONDS_PER_YEAR,
            endTime: _endTime
        });

        emit SetRecipient(_recipient, _yearlyAmount, _endTime);
    }

    /**
    * @notice withdraw salary
    */
    function withdraw(uint256 amount) external {
        updateRecipient(msg.sender);

        uint256 withdrawAmount = unclaimed[msg.sender] > amount ? amount : unclaimed[msg.sender];
        unclaimed[msg.sender] -= withdrawAmount;
        require(asset.transferFrom(treasuryAddress, msg.sender, withdrawAmount), "Payroll::withdraw: transfer failed");

        emit AmountWithdrawn(msg.sender, withdrawAmount);
    }

}