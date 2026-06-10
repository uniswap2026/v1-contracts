# @title Uniswap Exchange Interface V1 // Uniswap 交易所接口 V1
# @notice Source code found at https://github.com/uniswap // 源代码见 https://github.com/uniswap
# @notice Use at your own risk // 使用风险自负

contract Factory():
    def getExchange(token_addr: address) -> address: constant

contract Exchange():
    def getEthToTokenOutputPrice(tokens_bought: uint256) -> uint256(wei): constant
    def ethToTokenTransferInput(min_tokens: uint256, deadline: timestamp, recipient: address) -> uint256: modifying
    def ethToTokenTransferOutput(tokens_bought: uint256, deadline: timestamp, recipient: address) -> uint256(wei): modifying

TokenPurchase: event({buyer: indexed(address), eth_sold: indexed(uint256(wei)), tokens_bought: indexed(uint256)})
EthPurchase: event({buyer: indexed(address), tokens_sold: indexed(uint256), eth_bought: indexed(uint256(wei))})
AddLiquidity: event({provider: indexed(address), eth_amount: indexed(uint256(wei)), token_amount: indexed(uint256)})
RemoveLiquidity: event({provider: indexed(address), eth_amount: indexed(uint256(wei)), token_amount: indexed(uint256)})
Transfer: event({_from: indexed(address), _to: indexed(address), _value: uint256})
Approval: event({_owner: indexed(address), _spender: indexed(address), _value: uint256})

name: public(bytes32)                             # Uniswap V1 // Uniswap V1
symbol: public(bytes32)                           # UNI-V1 // UNI-V1
decimals: public(uint256)                         # 18 // 18
totalSupply: public(uint256)                      # total number of UNI in existence // UNI 总数量
balances: uint256[address]                        # UNI balance of an address // 地址的 UNI 余额
allowances: (uint256[address])[address]           # UNI allowance of one address on another // 一个地址对另一个地址的 UNI 授权额度
token: address(ERC20)                             # address of the ERC20 token traded on this contract // 在此合约上交易的 ERC20 代币地址
factory: Factory                                  # interface for the factory that created this contract // 创建此合约的工厂接口

# @dev This function acts as a contract constructor which is not currently supported in contracts deployed
#      using create_with_code_of(). It is called once by the factory during contract creation.
#      // 此函数充当合约构造函数，当前不支持在通过 create_with_code_of() 部署的合约中使用。
#      // 它在合约创建期间由工厂调用一次。
@public
def setup(token_addr: address):
    assert (self.factory == ZERO_ADDRESS and self.token == ZERO_ADDRESS) and token_addr != ZERO_ADDRESS
    self.factory = msg.sender
    self.token = token_addr
    self.name = 0x556e697377617020563100000000000000000000000000000000000000000000
    self.symbol = 0x554e492d56310000000000000000000000000000000000000000000000000000
    self.decimals = 18

# @notice Deposit ETH and Tokens (self.token) at current ratio to mint UNI tokens. // 以当前比例存入 ETH 和代币 (self.token) 以铸造 UNI 代币。
# @dev min_liquidity does nothing when total UNI supply is 0. // 当 UNI 总供应量为 0 时，min_liquidity 不起作用。
# @param min_liquidity Minimum number of UNI sender will mint if total UNI supply is greater than 0. // 如果 UNI 总供应量大于 0，发送者将铸造的最小 UNI 数量。
# @param max_tokens Maximum number of tokens deposited. Deposits max amount if total UNI supply is 0. // 存入的最大代币数量。如果 UNI 总供应量为 0，则存入最大数量。
# @param deadline Time after which this transaction can no longer be executed. // 交易无法执行的时间截止点。
# @return The amount of UNI minted. // 铸造的 UNI 数量。
@public
@payable
def addLiquidity(min_liquidity: uint256, max_tokens: uint256, deadline: timestamp) -> uint256:
    assert deadline > block.timestamp and (max_tokens > 0 and msg.value > 0)
    total_liquidity: uint256 = self.totalSupply
    if total_liquidity > 0:
        assert min_liquidity > 0
        eth_reserve: uint256(wei) = self.balance - msg.value
        token_reserve: uint256 = self.token.balanceOf(self)
        token_amount: uint256 = msg.value * token_reserve / eth_reserve + 1
        liquidity_minted: uint256 = msg.value * total_liquidity / eth_reserve
        assert max_tokens >= token_amount and liquidity_minted >= min_liquidity
        self.balances[msg.sender] += liquidity_minted
        self.totalSupply = total_liquidity + liquidity_minted
        assert self.token.transferFrom(msg.sender, self, token_amount)
        log.AddLiquidity(msg.sender, msg.value, token_amount)
        log.Transfer(ZERO_ADDRESS, msg.sender, liquidity_minted)
        return liquidity_minted
    else:
        assert (self.factory != ZERO_ADDRESS and self.token != ZERO_ADDRESS) and msg.value >= 1000000000
        assert self.factory.getExchange(self.token) == self
        token_amount: uint256 = max_tokens
        initial_liquidity: uint256 = as_unitless_number(self.balance)
        self.totalSupply = initial_liquidity
        self.balances[msg.sender] = initial_liquidity
        assert self.token.transferFrom(msg.sender, self, token_amount)
        log.AddLiquidity(msg.sender, msg.value, token_amount)
        log.Transfer(ZERO_ADDRESS, msg.sender, initial_liquidity)
        return initial_liquidity

# @dev Burn UNI tokens to withdraw ETH and Tokens at current ratio. // 燃烧 UNI 代币以按当前比例提取 ETH 和代币。
# @param amount Amount of UNI burned. // 燃烧的 UNI 数量。
# @param min_eth Minimum ETH withdrawn. // 提取的最小 ETH 数量。
# @param min_tokens Minimum Tokens withdrawn. // 提取的最小代币数量。
# @param deadline Time after which this transaction can no longer be executed. // 交易无法执行的时间截止点。
# @return The amount of ETH and Tokens withdrawn. // 提取的 ETH 和代币数量。
@public
def removeLiquidity(amount: uint256, min_eth: uint256(wei), min_tokens: uint256, deadline: timestamp) -> (uint256(wei), uint256):
    assert (amount > 0 and deadline > block.timestamp) and (min_eth > 0 and min_tokens > 0)
    total_liquidity: uint256 = self.totalSupply
    assert total_liquidity > 0
    token_reserve: uint256 = self.token.balanceOf(self)
    eth_amount: uint256(wei) = amount * self.balance / total_liquidity
    token_amount: uint256 = amount * token_reserve / total_liquidity
    assert eth_amount >= min_eth and token_amount >= min_tokens
    self.balances[msg.sender] -= amount
    self.totalSupply = total_liquidity - amount
    send(msg.sender, eth_amount)
    assert self.token.transfer(msg.sender, token_amount)
    log.RemoveLiquidity(msg.sender, eth_amount, token_amount)
    log.Transfer(msg.sender, ZERO_ADDRESS, amount)
    return eth_amount, token_amount

# @dev Pricing function for converting between ETH and Tokens. // ETH 和代币之间的定价函数。
# @param input_amount Amount of ETH or Tokens being sold. // 出售的 ETH 或代币数量。
# @param input_reserve Amount of ETH or Tokens (input type) in exchange reserves. // 交易所储备中的 ETH 或代币（输入类型）数量。
# @param output_reserve Amount of ETH or Tokens (output type) in exchange reserves. // 交易所储备中的 ETH 或代币（输出类型）数量。
# @return Amount of ETH or Tokens bought. // 购买的 ETH 或代币数量。
@private
@constant
def getInputPrice(input_amount: uint256, input_reserve: uint256, output_reserve: uint256) -> uint256:
    assert input_reserve > 0 and output_reserve > 0
    input_amount_with_fee: uint256 = input_amount * 997
    numerator: uint256 = input_amount_with_fee * output_reserve
    denominator: uint256 = (input_reserve * 1000) + input_amount_with_fee
    return numerator / denominator

# @dev Pricing function for converting between ETH and Tokens. // ETH 和代币之间的定价函数。
# @param output_amount Amount of ETH or Tokens being bought. // 购买的 ETH 或代币数量。
# @param input_reserve Amount of ETH or Tokens (input type) in exchange reserves. // 交易所储备中的 ETH 或代币（输入类型）数量。
# @param output_reserve Amount of ETH or Tokens (output type) in exchange reserves. // 交易所储备中的 ETH 或代币（输出类型）数量。
# @return Amount of ETH or Tokens sold. // 出售的 ETH 或代币数量。
@private
@constant
def getOutputPrice(output_amount: uint256, input_reserve: uint256, output_reserve: uint256) -> uint256:
    assert input_reserve > 0 and output_reserve > 0
    numerator: uint256 = input_reserve * output_amount * 1000
    denominator: uint256 = (output_reserve - output_amount) * 997
    return numerator / denominator + 1

@private
def ethToTokenInput(eth_sold: uint256(wei), min_tokens: uint256, deadline: timestamp, buyer: address, recipient: address) -> uint256:
    assert deadline >= block.timestamp and (eth_sold > 0 and min_tokens > 0)
    token_reserve: uint256 = self.token.balanceOf(self)
    tokens_bought: uint256 = self.getInputPrice(as_unitless_number(eth_sold), as_unitless_number(self.balance - eth_sold), token_reserve)
    assert tokens_bought >= min_tokens
    assert self.token.transfer(recipient, tokens_bought)
    log.TokenPurchase(buyer, eth_sold, tokens_bought)
    return tokens_bought

# @notice Convert ETH to Tokens. // 将 ETH 转换为代币。
# @dev User specifies exact input (msg.value). // 用户指定确切的输入 (msg.value)。
# @dev User cannot specify minimum output or deadline. // 用户无法指定最小输出或截止时间。
@public
@payable
def __default__():
    self.ethToTokenInput(msg.value, 1, block.timestamp, msg.sender, msg.sender)

# @notice Convert ETH to Tokens. // 将 ETH 转换为代币。
# @dev User specifies exact input (msg.value) and minimum output. // 用户指定确切的输入 (msg.value) 和最小输出。
# @param min_tokens Minimum Tokens bought. // 购买的最小代币数量。
# @param deadline Time after which this transaction can no longer be executed. // 交易无法执行的时间截止点。
# @return Amount of Tokens bought. // 购买的代币数量。
@public
@payable
def ethToTokenSwapInput(min_tokens: uint256, deadline: timestamp) -> uint256:
    return self.ethToTokenInput(msg.value, min_tokens, deadline, msg.sender, msg.sender)

# @notice Convert ETH to Tokens and transfers Tokens to recipient. // 将 ETH 转换为代币并将代币转账给接收者。
# @dev User specifies exact input (msg.value) and minimum output // 用户指定确切的输入 (msg.value) 和最小输出
# @param min_tokens Minimum Tokens bought. // 购买的最小代币数量。
# @param deadline Time after which this transaction can no longer be executed. // 交易无法执行的时间截止点。
# @param recipient The address that receives output Tokens. // 接收输出代币的地址。
# @return Amount of Tokens bought. // 购买的代币数量。
@public
@payable
def ethToTokenTransferInput(min_tokens: uint256, deadline: timestamp, recipient: address) -> uint256:
    assert recipient != self and recipient != ZERO_ADDRESS
    return self.ethToTokenInput(msg.value, min_tokens, deadline, msg.sender, recipient)

@private
def ethToTokenOutput(tokens_bought: uint256, max_eth: uint256(wei), deadline: timestamp, buyer: address, recipient: address) -> uint256(wei):
    assert deadline >= block.timestamp and (tokens_bought > 0 and max_eth > 0)
    token_reserve: uint256 = self.token.balanceOf(self)
    eth_sold: uint256 = self.getOutputPrice(tokens_bought, as_unitless_number(self.balance - max_eth), token_reserve)
    # Throws if eth_sold > max_eth  // 如果 eth_sold > max_eth 则抛出异常
    eth_refund: uint256(wei) = max_eth - as_wei_value(eth_sold, 'wei')
    if eth_refund > 0:
        send(buyer, eth_refund)
    assert self.token.transfer(recipient, tokens_bought)
    log.TokenPurchase(buyer, as_wei_value(eth_sold, 'wei'), tokens_bought)
    return as_wei_value(eth_sold, 'wei')

# @notice Convert ETH to Tokens. // 将 ETH 转换为代币。
# @dev User specifies maximum input (msg.value) and exact output. // 用户指定最大输入 (msg.value) 和确切输出。
# @param tokens_bought Amount of tokens bought. // 购买的代币数量。
# @param deadline Time after which this transaction can no longer be executed. // 交易无法执行的时间截止点。
# @return Amount of ETH sold. // 出售的 ETH 数量。
@public
@payable
def ethToTokenSwapOutput(tokens_bought: uint256, deadline: timestamp) -> uint256(wei):
    return self.ethToTokenOutput(tokens_bought, msg.value, deadline, msg.sender, msg.sender)

# @notice Convert ETH to Tokens and transfers Tokens to recipient. // 将 ETH 转换为代币并将代币转账给接收者。
# @dev User specifies maximum input (msg.value) and exact output. // 用户指定最大输入 (msg.value) 和确切输出。
# @param tokens_bought Amount of tokens bought. // 购买的代币数量。
# @param deadline Time after which this transaction can no longer be executed. // 交易无法执行的时间截止点。
# @param recipient The address that receives output Tokens. // 接收输出代币的地址。
# @return Amount of ETH sold. // 出售的 ETH 数量。
@public
@payable
def ethToTokenTransferOutput(tokens_bought: uint256, deadline: timestamp, recipient: address) -> uint256(wei):
    assert recipient != self and recipient != ZERO_ADDRESS
    return self.ethToTokenOutput(tokens_bought, msg.value, deadline, msg.sender, recipient)

@private
def tokenToEthInput(tokens_sold: uint256, min_eth: uint256(wei), deadline: timestamp, buyer: address, recipient: address) -> uint256(wei):
    assert deadline >= block.timestamp and (tokens_sold > 0 and min_eth > 0)
    token_reserve: uint256 = self.token.balanceOf(self)
    eth_bought: uint256 = self.getInputPrice(tokens_sold, token_reserve, as_unitless_number(self.balance))
    wei_bought: uint256(wei) = as_wei_value(eth_bought, 'wei')
    assert wei_bought >= min_eth
    send(recipient, wei_bought)
    assert self.token.transferFrom(buyer, self, tokens_sold)
    log.EthPurchase(buyer, tokens_sold, wei_bought)
    return wei_bought


# @notice Convert Tokens to ETH. // 将代币转换为 ETH。
# @dev User specifies exact input and minimum output. // 用户指定确切的输入和最小输出。
# @param tokens_sold Amount of Tokens sold. // 出售的代币数量。
# @param min_eth Minimum ETH purchased. // 购买的最小 ETH 数量。
# @param deadline Time after which this transaction can no longer be executed. // 交易无法执行的时间截止点。
# @return Amount of ETH bought. // 购买的 ETH 数量。
@public
def tokenToEthSwapInput(tokens_sold: uint256, min_eth: uint256(wei), deadline: timestamp) -> uint256(wei):
    return self.tokenToEthInput(tokens_sold, min_eth, deadline, msg.sender, msg.sender)

# @notice Convert Tokens to ETH and transfers ETH to recipient. // 将代币转换为 ETH 并将 ETH 转账给接收者。
# @dev User specifies exact input and minimum output. // 用户指定确切的输入和最小输出。
# @param tokens_sold Amount of Tokens sold. // 出售的代币数量。
# @param min_eth Minimum ETH purchased. // 购买的最小 ETH 数量。
# @param deadline Time after which this transaction can no longer be executed. // 交易无法执行的时间截止点。
# @param recipient The address that receives output ETH. // 接收输出 ETH 的地址。
# @return Amount of ETH bought. // 购买的 ETH 数量。
@public
def tokenToEthTransferInput(tokens_sold: uint256, min_eth: uint256(wei), deadline: timestamp, recipient: address) -> uint256(wei):
    assert recipient != self and recipient != ZERO_ADDRESS
    return self.tokenToEthInput(tokens_sold, min_eth, deadline, msg.sender, recipient)

@private
def tokenToEthOutput(eth_bought: uint256(wei), max_tokens: uint256, deadline: timestamp, buyer: address, recipient: address) -> uint256:
    assert deadline >= block.timestamp and eth_bought > 0
    token_reserve: uint256 = self.token.balanceOf(self)
    tokens_sold: uint256 = self.getOutputPrice(as_unitless_number(eth_bought), token_reserve, as_unitless_number(self.balance))
    # tokens sold is always > 0  // 出售的代币数量始终 > 0
    assert max_tokens >= tokens_sold
    send(recipient, eth_bought)
    assert self.token.transferFrom(buyer, self, tokens_sold)
    log.EthPurchase(buyer, tokens_sold, eth_bought)
    return tokens_sold

# @notice Convert Tokens to ETH. // 将代币转换为 ETH。
# @dev User specifies maximum input and exact output. // 用户指定最大输入和确切输出。
# @param eth_bought Amount of ETH purchased. // 购买的 ETH 数量。
# @param max_tokens Maximum Tokens sold. // 出售的最大代币数量。
# @param deadline Time after which this transaction can no longer be executed. // 交易无法执行的时间截止点。
# @return Amount of Tokens sold. // 出售的代币数量。
@public
def tokenToEthSwapOutput(eth_bought: uint256(wei), max_tokens: uint256, deadline: timestamp) -> uint256:
    return self.tokenToEthOutput(eth_bought, max_tokens, deadline, msg.sender, msg.sender)

# @notice Convert Tokens to ETH and transfers ETH to recipient. // 将代币转换为 ETH 并将 ETH 转账给接收者。
# @dev User specifies maximum input and exact output. // 用户指定最大输入和确切输出。
# @param eth_bought Amount of ETH purchased. // 购买的 ETH 数量。
# @param max_tokens Maximum Tokens sold. // 出售的最大代币数量。
# @param deadline Time after which this transaction can no longer be executed. // 交易无法执行的时间截止点。
# @param recipient The address that receives output ETH. // 接收输出 ETH 的地址。
# @return Amount of Tokens sold. // 出售的代币数量。
@public
def tokenToEthTransferOutput(eth_bought: uint256(wei), max_tokens: uint256, deadline: timestamp, recipient: address) -> uint256:
    assert recipient != self and recipient != ZERO_ADDRESS
    return self.tokenToEthOutput(eth_bought, max_tokens, deadline, msg.sender, recipient)

@private
def tokenToTokenInput(tokens_sold: uint256, min_tokens_bought: uint256, min_eth_bought: uint256(wei), deadline: timestamp, buyer: address, recipient: address, exchange_addr: address) -> uint256:
    assert (deadline >= block.timestamp and tokens_sold > 0) and (min_tokens_bought > 0 and min_eth_bought > 0)
    assert exchange_addr != self and exchange_addr != ZERO_ADDRESS
    token_reserve: uint256 = self.token.balanceOf(self)
    eth_bought: uint256 = self.getInputPrice(tokens_sold, token_reserve, as_unitless_number(self.balance))
    wei_bought: uint256(wei) = as_wei_value(eth_bought, 'wei')
    assert wei_bought >= min_eth_bought
    assert self.token.transferFrom(buyer, self, tokens_sold)
    tokens_bought: uint256 = Exchange(exchange_addr).ethToTokenTransferInput(min_tokens_bought, deadline, recipient, value=wei_bought)
    log.EthPurchase(buyer, tokens_sold, wei_bought)
    return tokens_bought

# @notice Convert Tokens (self.token) to Tokens (token_addr). // 将代币 (self.token) 转换为代币 (token_addr)。
# @dev User specifies exact input and minimum output. // 用户指定确切的输入和最小输出。
# @param tokens_sold Amount of Tokens sold. // 出售的代币数量。
# @param min_tokens_bought Minimum Tokens (token_addr) purchased. // 购买的最小代币 (token_addr) 数量。
# @param min_eth_bought Minimum ETH purchased as intermediary. // 作为中间购买的最小 ETH 数量。
# @param deadline Time after which this transaction can no longer be executed. // 交易无法执行的时间截止点。
# @param token_addr The address of the token being purchased. // 正在购买的代币地址。
# @return Amount of Tokens (token_addr) bought. // 购买的代币 (token_addr) 数量。
@public
def tokenToTokenSwapInput(tokens_sold: uint256, min_tokens_bought: uint256, min_eth_bought: uint256(wei), deadline: timestamp, token_addr: address) -> uint256:
    exchange_addr: address = self.factory.getExchange(token_addr)
    return self.tokenToTokenInput(tokens_sold, min_tokens_bought, min_eth_bought, deadline, msg.sender, msg.sender, exchange_addr)

# @notice Convert Tokens (self.token) to Tokens (token_addr) and transfers
#         Tokens (token_addr) to recipient. // 将代币 (self.token) 转换为代币 (token_addr) 并将代币 (token_addr) 转账给接收者。
# @dev User specifies exact input and minimum output. // 用户指定确切的输入和最小输出。
# @param tokens_sold Amount of Tokens sold. // 出售的代币数量。
# @param min_tokens_bought Minimum Tokens (token_addr) purchased. // 购买的最小代币 (token_addr) 数量。
# @param min_eth_bought Minimum ETH purchased as intermediary. // 作为中间购买的最小 ETH 数量。
# @param deadline Time after which this transaction can no longer be executed. // 交易无法执行的时间截止点。
# @param recipient The address that receives output ETH. // 接收输出 ETH 的地址。
# @param token_addr The address of the token being purchased. // 正在购买的代币地址。
# @return Amount of Tokens (token_addr) bought. // 购买的代币 (token_addr) 数量。
@public
def tokenToTokenTransferInput(tokens_sold: uint256, min_tokens_bought: uint256, min_eth_bought: uint256(wei), deadline: timestamp, recipient: address, token_addr: address) -> uint256:
    exchange_addr: address = self.factory.getExchange(token_addr)
    return self.tokenToTokenInput(tokens_sold, min_tokens_bought, min_eth_bought, deadline, msg.sender, recipient, exchange_addr)

@private
def tokenToTokenOutput(tokens_bought: uint256, max_tokens_sold: uint256, max_eth_sold: uint256(wei), deadline: timestamp, buyer: address, recipient: address, exchange_addr: address) -> uint256:
    assert deadline >= block.timestamp and (tokens_bought > 0 and max_eth_sold > 0)
    assert exchange_addr != self and exchange_addr != ZERO_ADDRESS
    eth_bought: uint256(wei) = Exchange(exchange_addr).getEthToTokenOutputPrice(tokens_bought)
    token_reserve: uint256 = self.token.balanceOf(self)
    tokens_sold: uint256 = self.getOutputPrice(as_unitless_number(eth_bought), token_reserve, as_unitless_number(self.balance))
    # tokens sold is always > 0  // 出售的代币数量始终 > 0
    assert max_tokens_sold >= tokens_sold and max_eth_sold >= eth_bought
    assert self.token.transferFrom(buyer, self, tokens_sold)
    eth_sold: uint256(wei) = Exchange(exchange_addr).ethToTokenTransferOutput(tokens_bought, deadline, recipient, value=eth_bought)
    log.EthPurchase(buyer, tokens_sold, eth_bought)
    return tokens_sold

# @notice Convert Tokens (self.token) to Tokens (token_addr). // 将代币 (self.token) 转换为代币 (token_addr)。
# @dev User specifies maximum input and exact output. // 用户指定最大输入和确切输出。
# @param tokens_bought Amount of Tokens (token_addr) bought. // 购买的代币 (token_addr) 数量。
# @param max_tokens_sold Maximum Tokens (self.token) sold. // 出售的最大代币 (self.token) 数量。
# @param max_eth_sold Maximum ETH purchased as intermediary. // 作为中间购买的最大 ETH 数量。
# @param deadline Time after which this transaction can no longer be executed. // 交易无法执行的时间截止点。
# @param token_addr The address of the token being purchased. // 正在购买的代币地址。
# @return Amount of Tokens (self.token) sold. // 出售的代币 (self.token) 数量。
@public
def tokenToTokenSwapOutput(tokens_bought: uint256, max_tokens_sold: uint256, max_eth_sold: uint256(wei), deadline: timestamp, token_addr: address) -> uint256:
    exchange_addr: address = self.factory.getExchange(token_addr)
    return self.tokenToTokenOutput(tokens_bought, max_tokens_sold, max_eth_sold, deadline, msg.sender, msg.sender, exchange_addr)

# @notice Convert Tokens (self.token) to Tokens (token_addr) and transfers
#         Tokens (token_addr) to recipient. // 将代币 (self.token) 转换为代币 (token_addr) 并将代币 (token_addr) 转账给接收者。
# @dev User specifies maximum input and exact output. // 用户指定最大输入和确切输出。
# @param tokens_bought Amount of Tokens (token_addr) bought. // 购买的代币 (token_addr) 数量。
# @param max_tokens_sold Maximum Tokens (self.token) sold. // 出售的最大代币 (self.token) 数量。
# @param max_eth_sold Maximum ETH purchased as intermediary. // 作为中间购买的最大 ETH 数量。
# @param deadline Time after which this transaction can no longer be executed. // 交易无法执行的时间截止点。
# @param recipient The address that receives output ETH. // 接收输出 ETH 的地址。
# @param token_addr The address of the token being purchased. // 正在购买的代币地址。
# @return Amount of Tokens (self.token) sold. // 出售的代币 (self.token) 数量。
@public
def tokenToTokenTransferOutput(tokens_bought: uint256, max_tokens_sold: uint256, max_eth_sold: uint256(wei), deadline: timestamp, recipient: address, token_addr: address) -> uint256:
    exchange_addr: address = self.factory.getExchange(token_addr)
    return self.tokenToTokenOutput(tokens_bought, max_tokens_sold, max_eth_sold, deadline, msg.sender, recipient, exchange_addr)

# @notice Convert Tokens (self.token) to Tokens (exchange_addr.token). // 将代币 (self.token) 转换为代币 (exchange_addr.token)。
# @dev Allows trades through contracts that were not deployed from the same factory. // 允许通过不是从同一工厂部署的合约进行交易。
# @dev User specifies exact input and minimum output. // 用户指定确切的输入和最小输出。
# @param tokens_sold Amount of Tokens sold. // 出售的代币数量。
# @param min_tokens_bought Minimum Tokens (token_addr) purchased. // 购买的最小代币 (token_addr) 数量。
# @param min_eth_bought Minimum ETH purchased as intermediary. // 作为中间购买的最小 ETH 数量。
# @param deadline Time after which this transaction can no longer be executed. // 交易无法执行的时间截止点。
# @param exchange_addr The address of the exchange for the token being purchased. // 正在购买的代币的交易所地址。
# @return Amount of Tokens (exchange_addr.token) bought. // 购买的代币 (exchange_addr.token) 数量。
@public
def tokenToExchangeSwapInput(tokens_sold: uint256, min_tokens_bought: uint256, min_eth_bought: uint256(wei), deadline: timestamp, exchange_addr: address) -> uint256:
    return self.tokenToTokenInput(tokens_sold, min_tokens_bought, min_eth_bought, deadline, msg.sender, msg.sender, exchange_addr)

# @notice Convert Tokens (self.token) to Tokens (exchange_addr.token) and transfers
#         Tokens (exchange_addr.token) to recipient. // 将代币 (self.token) 转换为代币 (exchange_addr.token) 并将代币 (exchange_addr.token) 转账给接收者。
# @dev Allows trades through contracts that were not deployed from the same factory. // 允许通过不是从同一工厂部署的合约进行交易。
# @dev User specifies exact input and minimum output. // 用户指定确切的输入和最小输出。
# @param tokens_sold Amount of Tokens sold. // 出售的代币数量。
# @param min_tokens_bought Minimum Tokens (token_addr) purchased. // 购买的最小代币 (token_addr) 数量。
# @param min_eth_bought Minimum ETH purchased as intermediary. // 作为中间购买的最小 ETH 数量。
# @param deadline Time after which this transaction can no longer be executed. // 交易无法执行的时间截止点。
# @param recipient The address that receives output ETH. // 接收输出 ETH 的地址。
# @param exchange_addr The address of the exchange for the token being purchased. // 正在购买的代币的交易所地址。
# @return Amount of Tokens (exchange_addr.token) bought. // 购买的代币 (exchange_addr.token) 数量。
@public
def tokenToExchangeTransferInput(tokens_sold: uint256, min_tokens_bought: uint256, min_eth_bought: uint256(wei), deadline: timestamp, recipient: address, exchange_addr: address) -> uint256:
    assert recipient != self
    return self.tokenToTokenInput(tokens_sold, min_tokens_bought, min_eth_bought, deadline, msg.sender, recipient, exchange_addr)

# @notice Convert Tokens (self.token) to Tokens (exchange_addr.token). // 将代币 (self.token) 转换为代币 (exchange_addr.token)。
# @dev Allows trades through contracts that were not deployed from the same factory. // 允许通过不是从同一工厂部署的合约进行交易。
# @dev User specifies maximum input and exact output. // 用户指定最大输入和确切输出。
# @param tokens_bought Amount of Tokens (token_addr) bought. // 购买的代币 (token_addr) 数量。
# @param max_tokens_sold Maximum Tokens (self.token) sold. // 出售的最大代币 (self.token) 数量。
# @param max_eth_sold Maximum ETH purchased as intermediary. // 作为中间购买的最大 ETH 数量。
# @param deadline Time after which this transaction can no longer be executed. // 交易无法执行的时间截止点。
# @param exchange_addr The address of the exchange for the token being purchased. // 正在购买的代币的交易所地址。
# @return Amount of Tokens (self.token) sold. // 出售的代币 (self.token) 数量。
@public
def tokenToExchangeSwapOutput(tokens_bought: uint256, max_tokens_sold: uint256, max_eth_sold: uint256(wei), deadline: timestamp, exchange_addr: address) -> uint256:
    return self.tokenToTokenOutput(tokens_bought, max_tokens_sold, max_eth_sold, deadline, msg.sender, msg.sender, exchange_addr)

# @notice Convert Tokens (self.token) to Tokens (exchange_addr.token) and transfers
#         Tokens (exchange_addr.token) to recipient. // 将代币 (self.token) 转换为代币 (exchange_addr.token) 并将代币 (exchange_addr.token) 转账给接收者。
# @dev Allows trades through contracts that were not deployed from the same factory. // 允许通过不是从同一工厂部署的合约进行交易。
# @dev User specifies maximum input and exact output. // 用户指定最大输入和确切输出。
# @param tokens_bought Amount of Tokens (token_addr) bought. // 购买的代币 (token_addr) 数量。
# @param max_tokens_sold Maximum Tokens (self.token) sold. // 出售的最大代币 (self.token) 数量。
# @param max_eth_sold Maximum ETH purchased as intermediary. // 作为中间购买的最大 ETH 数量。
# @param deadline Time after which this transaction can no longer be executed. // 交易无法执行的时间截止点。
# @param recipient The address that receives output ETH. // 接收输出 ETH 的地址。
# @param token_addr The address of the token being purchased. // 正在购买的代币地址。
# @return Amount of Tokens (self.token) sold. // 出售的代币 (self.token) 数量。
@public
def tokenToExchangeTransferOutput(tokens_bought: uint256, max_tokens_sold: uint256, max_eth_sold: uint256(wei), deadline: timestamp, recipient: address, exchange_addr: address) -> uint256:
    assert recipient != self
    return self.tokenToTokenOutput(tokens_bought, max_tokens_sold, max_eth_sold, deadline, msg.sender, recipient, exchange_addr)

# @notice Public price function for ETH to Token trades with an exact input. // ETH 到代币交易精确输入的公开价格函数。
# @param eth_sold Amount of ETH sold. // 出售的 ETH 数量。
# @return Amount of Tokens that can be bought with input ETH. // 可以用输入 ETH 购买的代币数量。
@public
@constant
def getEthToTokenInputPrice(eth_sold: uint256(wei)) -> uint256:
    assert eth_sold > 0
    token_reserve: uint256 = self.token.balanceOf(self)
    return self.getInputPrice(as_unitless_number(eth_sold), as_unitless_number(self.balance), token_reserve)

# @notice Public price function for ETH to Token trades with an exact output. // ETH 到代币交易精确输出的公开价格函数。
# @param tokens_bought Amount of Tokens bought. // 购买的代币数量。
# @return Amount of ETH needed to buy output Tokens. // 购买输出代币所需的 ETH 数量。
@public
@constant
def getEthToTokenOutputPrice(tokens_bought: uint256) -> uint256(wei):
    assert tokens_bought > 0
    token_reserve: uint256 = self.token.balanceOf(self)
    eth_sold: uint256 = self.getOutputPrice(tokens_bought, as_unitless_number(self.balance), token_reserve)
    return as_wei_value(eth_sold, 'wei')

# @notice Public price function for Token to ETH trades with an exact input. // 代币到 ETH 交易精确输入的公开价格函数。
# @param tokens_sold Amount of Tokens sold. // 出售的代币数量。
# @return Amount of ETH that can be bought with input Tokens. // 可以用输入代币购买的 ETH 数量。
@public
@constant
def getTokenToEthInputPrice(tokens_sold: uint256) -> uint256(wei):
    assert tokens_sold > 0
    token_reserve: uint256 = self.token.balanceOf(self)
    eth_bought: uint256 = self.getInputPrice(tokens_sold, token_reserve, as_unitless_number(self.balance))
    return as_wei_value(eth_bought, 'wei')

# @notice Public price function for Token to ETH trades with an exact output. // 代币到 ETH 交易精确输出的公开价格函数。
# @param eth_bought Amount of output ETH. // 输出 ETH 的数量。
# @return Amount of Tokens needed to buy output ETH. // 购买输出 ETH 所需的代币数量。
@public
@constant
def getTokenToEthOutputPrice(eth_bought: uint256(wei)) -> uint256:
    assert eth_bought > 0
    token_reserve: uint256 = self.token.balanceOf(self)
    return self.getOutputPrice(as_unitless_number(eth_bought), token_reserve, as_unitless_number(self.balance))

# @return Address of Token that is sold on this exchange. // 在此交易所出售的代币地址。
@public
@constant
def tokenAddress() -> address:
    return self.token

# @return Address of factory that created this exchange. // 创建此交易所的工厂地址。
@public
@constant
def factoryAddress() -> address(Factory):
    return self.factory

# ERC20 compatibility for exchange liquidity modified from
# https://github.com/ethereum/vyper/blob/master/examples/tokens/ERC20.vy
# // 交易所流动性的 ERC20 兼容性，修改自
# // https://github.com/ethereum/vyper/blob/master/examples/tokens/ERC20.vy
@public
@constant
def balanceOf(_owner : address) -> uint256:
    return self.balances[_owner]

@public
def transfer(_to : address, _value : uint256) -> bool:
    self.balances[msg.sender] -= _value
    self.balances[_to] += _value
    log.Transfer(msg.sender, _to, _value)
    return True

@public
def transferFrom(_from : address, _to : address, _value : uint256) -> bool:
    self.balances[_from] -= _value
    self.balances[_to] += _value
    self.allowances[_from][msg.sender] -= _value
    log.Transfer(_from, _to, _value)
    return True

@public
def approve(_spender : address, _value : uint256) -> bool:
    self.allowances[msg.sender][_spender] = _value
    log.Approval(msg.sender, _spender, _value)
    return True

@public
@constant
def allowance(_owner : address, _spender : address) -> uint256:
    return self.allowances[_owner][_spender]
