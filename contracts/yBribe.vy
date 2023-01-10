# @version 0.3.7

from vyper.interfaces import ERC20
from vyper.interfaces import ERC20Detailed

struct VotedSlope:
    slope: uint256
    power: uint256
    end: uint256

struct Point:
    bias: uint256
    slope: uint256

interface GaugeController:
    def gauge_types(gauge: address) -> int128: view
    def last_user_vote(user: address, gauge: address) -> uint256: view
    def vote_user_slopes(user: address, gauge: address) -> VotedSlope: view
    def checkpoint_gauge(gauge: address): nonpayable
    def points_weight(gauge: address, period: uint256) ->  Point: view

struct Bribe:
    gauge: address
    owner: address # Address with ability to modify bribe parameters
    reward_token: address
    reward_amount: uint256
    duration: uint256 # Number of periods
    end: uint256
    blocked_list: DynArray[address, 100]

struct Period:
    period_id: uint256
    ts: uint256
    reward_per_period: uint256

struct ModifiedBribe:
    duration: uint256
    reward_amount: uint256
    end: uint256
    blocked_list: DynArray[address, 100]

event Claimed:
    user: indexed(address)
    reward_token: indexed(address)
    bribe_id: indexed(uint256)
    amount: uint256
    current_period: uint256

event BribeAdded:
    bribe_id: indexed(uint256)
    gauge: indexed(address)
    owner: address
    reward_token: indexed(address)
    num_periods_duration: uint256
    reward_amount_per_period: uint256
    reward_amount: uint256
    deposit_fee: uint256

event PeriodRolledOver:
    bribe_id: uint256
    index: uint8
    period: uint256
    reward_amount_per_period: uint256

event BribeClosed:
    bribe_id: uint256
    remainingReward: uint256

PRECISION: constant(uint256) = 10**18
WEEK: constant(uint256) = 60 * 60 * 24 * 7
next_id: public(uint256)
deposit_fee: public(uint256)
gauge_controller: constant(address) = 0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB

fee_recipient: public(address)
is_blocked: public(HashMap[uint256, HashMap[address, bool]])
claim_delegate: public(HashMap[address, address])
next_claim_time: public(HashMap[uint256, HashMap[address, uint256]]) # Tracks a user's next claim time after removed from blacklist
last_user_claim: public(HashMap[address, HashMap[uint256, uint256]])
active_period: public(HashMap[uint256, Period])
bribes: public(HashMap[uint256, Bribe])
modified_bribe_queue: public(HashMap[uint256, ModifiedBribe])
amount_claimed: public(HashMap[uint256, uint256])
reward_per_token: public(HashMap[uint256, uint256])
claim_recipient: public(HashMap[address, address])

@external
def __init__():
    self.deposit_fee = 10**16 # 1%
    self.fee_recipient = 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52

@external
def add_bribe(
    gauge: address,
    reward_token: address,
    reward_amount: uint256,
    num_periods_duration: uint256,
    blocked_list: DynArray[address, 100],
    start_period: uint256 = 0
) -> uint256:
    """
    @notice Create a new bribe.
    @param gauge Address of the target gauge.
    @param reward_token Address of the ERC20 used or rewards.
    @param reward_amount Sum total of reward amount to add.
    @param duration length of bribe in terms of periods.
    @param blacklist Array of addresses to blacklist.
    @return newBribeID of the bribe created.
    """
    assert GaugeController(gauge_controller).gauge_types(gauge) >= 0 # Block if gauge not added to controller
    assert reward_token.is_contract
    assert reward_amount > 0
    assert num_periods_duration > 0
    assert start_period == 0 or start_period > self.current_period()
    
    _start_period: uint256 = start_period
    if _start_period == 0:
        _start_period = self.current_period() + WEEK
    bribe_id: uint256 = self.next_id
    self.next_id += 1 # Increment global counter

    ERC20(reward_token).transferFrom(msg.sender, self, reward_amount, default_return_value=True)
    # Compute fee
    fee: uint256 = reward_amount * self.deposit_fee / PRECISION
    _reward_amount: uint256 = reward_amount
    if fee > 0:
        ERC20(reward_token).transfer(self.fee_recipient, fee, default_return_value=True)
        _reward_amount -= fee
    
    reward_amount_per_period: uint256 = _reward_amount / num_periods_duration

    self.bribes[bribe_id] = Bribe({
        gauge: gauge,
        owner: msg.sender,
        reward_token: reward_token,
        reward_amount: _reward_amount,
        duration: duration,
        end: self.current_period() + WEEK * (duration + 1),
        blocked_list: blocked_list
    })

    log BribeAdded(
        bribe_id,
        gauge,
        msg.sender,
        reward_token,
        duration,
        reward_amount_per_period,
        _reward_amount,
        fee
    )
    
    self.active_period[bribe_id] = Period({
        period_id: 0, 
        ts: self.current_period() + (num_periods_duration * WEEK), 
        reward_per_period: reward_amount_per_period
    })

    for blocked_address in blocked_list:
        self.is_blocked[bribe_id][blocked_address] = True
    
    return bribe_id

@external
def claim_reward(bribe_id: uint256) -> uint256:
    return self._claim(msg.sender, bribe_id)

@external
def claim_reward_for(user: address, bribe_id: uint256) -> uint256: 
    return self._claim(user, bribe_id)

@internal
def _claim(user: address, bribe_id: uint256) -> uint256:
    permitted: bool = msg.sender == user or (
        self.claim_delegate[user] == ZERO_ADDRESS or self.claim_delegate[user] == msg.sender
    )
    if not permitted or self.is_blocked[bribe_id][user] or self.next_claim_time[bribe_id][user] > self.current_period():
        return 0
    
    current_period: uint256 = self._update_period(bribe_id)

    bribe: Bribe = self.bribes[bribe_id]

    gauge: address = bribe.gauge
    end: uint256 = bribe.end
    last_vote: uint256 = GaugeController(gauge_controller).last_user_vote(user, gauge)
    vs: VotedSlope = GaugeController(gauge_controller).vote_user_slopes(user, gauge)

    if (
        vs.slope == 0 or
        self.last_user_claim[user][bribe_id] >= current_period or
        current_period >= end or
        current_period <= last_vote or 
        current_period >= end or
        current_period != self.current_period() or # This maybe we can remove
        self.amount_claimed[bribe_id] == bribe.reward_amount
    ):
        return 0

    self.last_user_claim[user][bribe_id] = current_period

    bias: uint256 = self.get_bias(vs.slope, vs.end, current_period)
    amount: uint256 = bias * self.reward_per_token[bribe_id] / PRECISION

    _amount_claimed: uint256 = self.amount_claimed[bribe_id]
    if amount + _amount_claimed > bribe.reward_amount:
        amount = bribe.reward_amount - _amount_claimed

    self.amount_claimed[bribe_id] += amount

    recipient: address = self.claim_recipient[user]
    if recipient == ZERO_ADDRESS:
        recipient = user
    ERC20(bribe.reward_token).transfer(recipient, amount, default_return_value=True)


    log Claimed(user, bribe.reward_token, bribe_id, amount, current_period)

    return amount

@internal
def _update_period(bribe_id: uint256) -> uint256:
    _active_period: Period = self.active_period[bribe_id]
    current_period: uint256 = self.current_period()

    if _active_period.period_id == 0 and current_period == _active_period.ts:
        # Initialize reward per token.
        # Only for the first period, and if not already initialized.
        self._update_reward_per_token(bribe_id, current_period)

    # Increase Period
    if block.timestamp >= _active_period.ts + WEEK:
        # Checkpoint gauge to have up to date gauge weight.
        GaugeController(gauge_controller).checkpoint_gauge(self.bribes[bribe_id].gauge)
        self.roll_over(bribe_id, current_period)
        return current_period

    return _active_period.ts


@internal
@view
def _get_adjusted_bias(gauge: address, blocked_list: DynArray[address, 100], period: uint256) -> uint256:
    """
    @notice Get adjusted slope from Gauge Controller for a given gauge address. Remove the weight of blacklisted addresses.
    @param gauge Address of the gauge.
    @param blocked_list Array of blacklisted addresses.
    @param period Timestamp to check vote weight.
    """
    gauge_bias: uint256 = GaugeController(gauge_controller).points_weight(gauge, period).bias

    for blocked_address in blocked_list:
        voted_slope: VotedSlope = GaugeController(gauge_controller).vote_user_slopes(blocked_address, gauge)
        last_vote: uint256 = GaugeController(gauge_controller).last_user_vote(blocked_address, gauge)
        if (period > last_vote):
            # Reduce by blocked user bias
            gauge_bias -= self.get_bias(voted_slope.slope, voted_slope.end, period)
    return gauge_bias


@internal
def _update_reward_per_token(bribe_id: uint256, current_period: uint256):
    """
    @notice Update the amount of reward per token for a given bribe.
    @dev This function is only called once per Bribe.
    """
    if self.reward_per_token[bribe_id] == 0:
        gauge_bias: uint256 = self._get_adjusted_bias(self.bribes[bribe_id].gauge, self.bribes[bribe_id].blocked_list, current_period)
        if gauge_bias != 0:
            self.reward_per_token[bribe_id] = self.active_period[bribe_id].reward_per_period * PRECISION / gauge_bias

@internal
@view
def active_period_per_bribe(bribe_id: uint256) -> uint8:
    bribe: Bribe = self.bribes[bribe_id]

    end: uint256 = bribe.end
    duration: uint256 = bribe.duration
    periods_left: uint256 = 0
    if end > self.current_period():
        periods_left = (end - self.current_period()) / WEEK

    # If periods_left is greater, then the bribe hasn't started yet.
    if periods_left > duration:
        return 0
    return convert(duration - periods_left, uint8)

@external
@view
def get_active_period_per_bribe(bribe_id: uint256) -> uint8:
    """
    @notice Lookup current period index for given bribe
    @param bribe_id Bribe to lookup
    """
    return self.active_period_per_bribe(bribe_id)

@internal
@view
def periods_left(bribe_id: uint256) -> uint256:
    bribe: Bribe = self.bribes[bribe_id]
    end: uint256 = bribe.end
    if end > self.current_period():
        return (end - self.current_period()) / WEEK
    return 0

@external
@view
def get_periods_left(bribe_id: uint256) -> uint256:
    """
    @notice Check number of remaining periods
    @param bribe_id Bribe to get remaining periods for
    """
    return self.periods_left(bribe_id)


@internal
def roll_over(bribe_id: uint256, current_period: uint256):
    """
    @notice Make all updates and bribe modificiations transitioning into new period
    @param bribe_id Bribe to roll-over
    @param current_period Period to roll-over to
    """
    index: uint8 = self.active_period_per_bribe(bribe_id)

    modified_bribe: ModifiedBribe = self.modified_bribe_queue[bribe_id]

    # Check if there is an upgrade in queue.
    if modified_bribe.reward_amount != 0:
        self.bribes[bribe_id].duration = modified_bribe.duration
        self.bribes[bribe_id].reward_amount = modified_bribe.reward_amount
        self.bribes[bribe_id].end = modified_bribe.end
        self.bribes[bribe_id].blocked_list = modified_bribe.blocked_list
        # Clear storage
        self.modified_bribe_queue[bribe_id] = empty(ModifiedBribe)

    bribe: Bribe = self.bribes[bribe_id]

    periods_left: uint256 = self.periods_left(bribe_id)
    reward_per_period: uint256 = bribe.reward_amount - self.amount_claimed[bribe_id]

    if bribe.end > current_period + WEEK and periods_left > 1:
        reward_per_period = reward_per_period / periods_left

    # Get adjusted slope without blacklisted addresses.
    gauge_bias: uint256 = self._get_adjusted_bias(bribe.gauge, bribe.blocked_list, current_period)

    self.reward_per_token[bribe_id] = reward_per_period * PRECISION / gauge_bias
    self.active_period[bribe_id] = Period({
        period_id: convert(index, uint256), 
        ts: current_period,
        reward_per_period: reward_per_period
    })

    log PeriodRolledOver(bribe_id, index, current_period, reward_per_period)

@internal
@view
def current_period() -> uint256:
    return block.timestamp / WEEK * WEEK

@external
@view
def get_current_period() -> uint256:
    """
    @notice Get timestamp of current period
    """
    return self.current_period()

@internal
@view
def get_bias(slope: uint256, end: uint256, current_period: uint256) -> uint256:
    """
    @notice Compute the bias associated with a specific user's gauge vote
    """
    if current_period + WEEK >= end:
        return 0
    return slope * (end - current_period)

@external
def get_queued_modified_bribe(bribe_id: uint256) -> ModifiedBribe:
    """
    @notice The modify queue represents pending modifications to an existing bribe to be enacted in the following period
    @dev An empty object is returned if no modified bribe is pending
    @param bribe_id of the bribe to check for modifications
    """
    return self.modified_bribe_queue[bribe_id]

@external
def get_bribe(bribe_id: uint256) -> Bribe:
    """
    @notice Return the bribe object for a given ID
    @param bribe_id of the bribe
    """
    return self.bribes[bribe_id]


@nonreentrant("lock")
@external
def close_bribe(bribe_id: uint256):
    assert msg.sender == self.bribes[bribe_id].owner #dev: not allowed
    bribe: Bribe = self.bribes[bribe_id]

    if self.current_period() >= bribe.end:
        left_over: uint256 = 0
        modified_bribe: ModifiedBribe = self.modified_bribe_queue[bribe_id]
        if modified_bribe.reward_amount != 0:
            leftOver = modified_bribe.reward_amount - self.amount_claimed[bribe_id]
            clear(self.modified_bribe_queue[bribeId])
        else:
            leftOver = self.bribes[bribeId].reward_amount - amountClaimed[bribeId]
        
        ERC20(bribe.reward_token).transferFrom(bribe.owner, leftOver, default_return_value=True)
        clear(bribes[bribeId].owner)

        log BribeClosed(bribeId, leftOver)

"""
    Cleanup comments
    def close_bribe
    def update_owner
    def update_operator
    def update_fee
    def update_claim_recipient
    def update_fee_recipient
    def modify_bribe # duration, blacklist, etc
"""