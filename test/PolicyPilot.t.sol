// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {PolicyPilot} from "../src/PolicyPilot.sol";
import {MockToken} from "../src/MockToken.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract PolicyPilotTest is Test {
    PolicyPilot pp; MockToken t;
    address admin = address(0xA11CE); address exec = address(0xE0); address bob = address(0xB0B); address eve = address(0xEEE);
    uint256 constant LIMIT = 100e18; uint256 constant BUDGET = 250e18;

    function setUp() public {
        t = new MockToken();
        pp = new PolicyPilot(IERC20(address(t)), admin, exec, LIMIT, BUDGET);
        t.mint(address(pp), 1000e18);
        vm.prank(admin); pp.setRecipient(bob, true);
    }
    function test_ConstructorZeroAddress() public {
        vm.expectRevert(PolicyPilot.ZeroAddress.selector);
        new PolicyPilot(IERC20(address(0)), admin, exec, 1, 1);
        vm.expectRevert(PolicyPilot.ZeroAddress.selector);
        new PolicyPilot(IERC20(address(t)), address(0), exec, 1, 1);
        vm.expectRevert(PolicyPilot.ZeroAddress.selector);
        new PolicyPilot(IERC20(address(t)), admin, address(0), 1, 1);
    }
    function test_ExecuteHappyPath() public {
        vm.expectEmit(true, true, false, true);
        emit PolicyPilot.Executed(bytes32("r1"), bob, 50e18, 50e18);
        vm.prank(exec); pp.execute("r1", bob, 50e18);
        assertEq(t.balanceOf(bob), 50e18); assertEq(pp.totalSpent(), 50e18); assertTrue(pp.executed("r1"));
    }
    function test_RevertNotExecutor() public {
        vm.expectRevert(PolicyPilot.NotExecutor.selector);
        vm.prank(eve); pp.execute("r1", bob, 1);
    }
    function test_RevertReplay() public {
        vm.startPrank(exec); pp.execute("r1", bob, 1);
        vm.expectRevert(abi.encodeWithSelector(PolicyPilot.RequestAlreadyExecuted.selector, bytes32("r1")));
        pp.execute("r1", bob, 1);
    }
    function test_RevertRecipientNotAllowed() public {
        vm.expectRevert(abi.encodeWithSelector(PolicyPilot.RecipientNotAllowed.selector, eve));
        vm.prank(exec); pp.execute("r1", eve, 1);
    }
    function test_RevertPerRequestLimit() public {
        vm.expectRevert(abi.encodeWithSelector(PolicyPilot.PerRequestLimitExceeded.selector, LIMIT + 1, LIMIT));
        vm.prank(exec); pp.execute("r1", bob, LIMIT + 1);
    }
    function test_RevertBudgetExceeded() public {
        vm.startPrank(exec); pp.execute("a", bob, 100e18); pp.execute("b", bob, 100e18);
        vm.expectRevert(abi.encodeWithSelector(PolicyPilot.BudgetExceeded.selector, 51e18, 50e18));
        pp.execute("c", bob, 51e18);
        pp.execute("d", bob, 50e18); assertEq(pp.remainingBudget(), 0);
    }
    function test_RevertZeroAmount() public {
        vm.expectRevert(PolicyPilot.ZeroAmount.selector);
        vm.prank(exec); pp.execute("r1", bob, 0);
    }
    function test_PauseBlocksAndUnpause() public {
        vm.prank(admin); pp.setPaused(true);
        vm.expectRevert(PolicyPilot.Paused.selector);
        vm.prank(exec); pp.execute("r1", bob, 1);
        vm.prank(admin); pp.setPaused(false);
        vm.prank(exec); pp.execute("r1", bob, 1);
    }
    function test_FailedRequestNotConsumed() public {
        vm.prank(exec); vm.expectRevert(); pp.execute("r1", bob, LIMIT + 1);
        assertFalse(pp.executed("r1"));
        vm.prank(exec); pp.execute("r1", bob, 1);
    }
    function test_AdminOnlySetters() public {
        vm.startPrank(eve);
        vm.expectRevert(PolicyPilot.NotAdmin.selector); pp.setRecipient(eve, true);
        vm.expectRevert(PolicyPilot.NotAdmin.selector); pp.setExecutor(eve);
        vm.expectRevert(PolicyPilot.NotAdmin.selector); pp.transferAdmin(eve);
        vm.expectRevert(PolicyPilot.NotAdmin.selector); pp.setPerRequestLimit(1);
        vm.expectRevert(PolicyPilot.NotAdmin.selector); pp.setBudget(1);
        vm.expectRevert(PolicyPilot.NotAdmin.selector); pp.setPaused(true);
    }
    function test_AdminSettersWork() public {
        vm.startPrank(admin);
        pp.setExecutor(eve); assertEq(pp.executor(), eve);
        pp.setPerRequestLimit(5); assertEq(pp.perRequestLimit(), 5);
        pp.setBudget(7); assertEq(pp.budget(), 7);
        pp.setRecipient(bob, false); assertFalse(pp.allowedRecipient(bob));
        vm.expectRevert(PolicyPilot.ZeroAddress.selector); pp.setRecipient(address(0), true);
        vm.expectRevert(PolicyPilot.ZeroAddress.selector); pp.setExecutor(address(0));
        vm.expectRevert(PolicyPilot.ZeroAddress.selector); pp.transferAdmin(address(0));
        pp.transferAdmin(eve); assertEq(pp.admin(), eve);
        vm.expectRevert(PolicyPilot.NotAdmin.selector); pp.setPaused(true);
    }
    function test_BudgetLoweredBelowSpent() public {
        vm.prank(exec); pp.execute("a", bob, 100e18);
        vm.prank(admin); pp.setBudget(10e18);
        assertEq(pp.remainingBudget(), 0);
        vm.expectRevert(abi.encodeWithSelector(PolicyPilot.BudgetExceeded.selector, 1, 0));
        vm.prank(exec); pp.execute("b", bob, 1);
    }
    function test_InsufficientTokenBalanceRevertsAtomically() public {
        PolicyPilot p2 = new PolicyPilot(IERC20(address(t)), admin, exec, LIMIT, BUDGET);
        vm.prank(admin); p2.setRecipient(bob, true);
        vm.prank(exec); vm.expectRevert(); p2.execute("x", bob, 1);
        assertEq(p2.totalSpent(), 0); assertFalse(p2.executed("x"));
    }
    function testFuzz_ExecuteRespectsBounds(bytes32 id, uint256 amt) public {
        vm.prank(exec);
        if (amt == 0 || amt > LIMIT) { vm.expectRevert(); pp.execute(id, bob, amt); assertEq(pp.totalSpent(), 0); }
        else { pp.execute(id, bob, amt); assertEq(t.balanceOf(bob), amt); }
    }
    function testFuzz_NonExecutorAlwaysReverts(address caller, uint256 amt) public {
        vm.assume(caller != exec);
        vm.expectRevert(PolicyPilot.NotExecutor.selector);
        vm.prank(caller); pp.execute("z", bob, amt);
    }
}

contract Handler is Test {
    PolicyPilot pp; address exec; address bob; uint256 public ghostSpent; uint256 public calls;
    constructor(PolicyPilot p, address e, address b) { pp = p; exec = e; bob = b; }
    function exec_(uint256 seed, uint256 amt) external {
        amt = bound(amt, 0, 150e18); bytes32 id = bytes32(seed % 20);
        vm.prank(exec);
        try pp.execute(id, bob, amt) { ghostSpent += amt; calls++; } catch {}
    }
}

contract PolicyPilotInvariant is StdInvariant, Test {
    PolicyPilot pp; MockToken t; Handler h; address bob = address(0xB0B);
    function setUp() public {
        t = new MockToken();
        pp = new PolicyPilot(IERC20(address(t)), address(this), address(0xE0), 100e18, 250e18);
        t.mint(address(pp), 1000e18); pp.setRecipient(bob, true);
        h = new Handler(pp, address(0xE0), bob); targetContract(address(h));
    }
    function invariant_SpentNeverExceedsBudget() public view { assertLe(pp.totalSpent(), pp.budget()); }
    function invariant_SpentMatchesTransfers() public view {
        assertEq(pp.totalSpent(), h.ghostSpent()); assertEq(t.balanceOf(bob), pp.totalSpent());
        assertEq(t.balanceOf(address(pp)) + pp.totalSpent(), 1000e18);
    }
    function invariant_AtMost20Executions() public view { assertLe(h.calls(), 20); }
}
