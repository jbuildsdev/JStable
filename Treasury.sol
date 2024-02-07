
pragma solidity ^0.8.0;

contract Treasury {
    address payable public owner;

    constructor() {
        owner = payable(msg.sender);
    }

    receive() external payable {}

    function withdraw() external {
        require(msg.sender == owner, "Only the owner can withdraw funds");
        uint256 balance = address(this).balance;
        owner.transfer(balance);
    }
}
