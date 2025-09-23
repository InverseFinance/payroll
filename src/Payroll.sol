pragma solidity 0.8.13;

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

contract Payroll {

    mapping(address => Recipient) public recipients;
    mapping(address => uint256) public unclaimed;

    address public immutable treasuryAddress;
    address public immutable governance;
    IERC20 public immutable DOLA;
    
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    struct Recipient {
        uint256 lastClaim;
        uint256 ratePerSecond;
        uint256 endTime;
    }

    event SetRecipient(address recipient, uint256 amount, uint256 endTime);
    event RecipientRemoved(address recipient);
    event AmountWithdrawn(address recipient, uint256 amount);

    constructor(address _treasuryAddress, address _governance, address _DOLA) {
        treasuryAddress = _treasuryAddress;
        governance = _governance;
        DOLA = IERC20(_DOLA);
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
        require(msg.sender == governance, "DolaPayroll::setRecipient: only governance");
        require(_recipient != address(0), "DolaPayroll::setRecipient: zero address!");

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
        require(DOLA.transferFrom(treasuryAddress, msg.sender, withdrawAmount), "DolaPayroll::withdraw: transfer failed");

        emit AmountWithdrawn(msg.sender, withdrawAmount);
    }

}