# Uniswap V1 架构文档

## 概述

Uniswap V1 是一个去中心化交易协议，由两个核心合约组成：
- **Factory 合约** (`uniswap_factory.vy`): 用于创建和管理 ERC20 代币的交易所合约
- **Exchange 合约** (`uniswap_exchange.vy`): 每个 ERC20 代币独立部署，负责实际执行 ETH 和该代币之间的交换

---

## 部署

| 网络    | Factory 合约                                 | ExchangeTemplate 合约                        |
| ------- | -------------------------------------------- | -------------------------------------------- |
| Mainnet | `0xc0a47dFe034B400B47bDaD5FecDa2621de6c4d95` | `0x2157A7894439191e520825fe9399aB8655E0f708` |

---

## 主入口点

### 1. Factory 合约入口点

| 函数                          | 说明                                | 权限       |
| ----------------------------- | ----------------------------------- | ---------- |
| `initializeFactory(template)` | 初始化工厂，设置交易所模板地址      | 仅首次调用 |
| `createExchange(token)`       | 为指定 ERC20 代币创建新的交易所合约 | 任何人     |

### 2. Exchange 合约入口点

| 函数                         | 说明                                        | 权限       |
| ---------------------------- | ------------------------------------------- | ---------- |
| `setup(token_addr)`          | 合约初始化（构造函数替代），由工厂调用一次  | 仅工厂     |
| `__default__()`              | 默认回退函数，处理直接发送 ETH 进行代币购买 | 任何人     |
| `addLiquidity()`             | 添加流动性，存入 ETH 和代币对               | 代币持有者 |
| `removeLiquidity()`          | 移除流动性，提取 ETH 和代币                 | UNI 持有者 |
| `ethToTokenSwapInput()`      | 用固定 ETH 数量交换代币                     | 任何人     |
| `ethToTokenSwapOutput()`     | 用最多 ETH 数量换取固定代币数量             | 任何人     |
| `tokenToEthSwapInput()`      | 用固定代币数量交换 ETH                      | 任何人     |
| `tokenToEthSwapOutput()`     | 用最多代币数量换取固定 ETH 数量             | 任何人     |
| `tokenToTokenSwapInput()`    | 通过 ETH 中继进行代币到代币交换             | 任何人     |
| `tokenToExchangeSwapInput()` | 跨工厂进行代币交换                          | 任何人     |

---

## 核心业务逻辑（按功能分类）

### 一、基础层：合约创建与初始化

#### 1.1 工厂初始化
```
initializeFactory(template)
├── 验证：exchangeTemplate 必须为零地址（防止重复初始化）
├── 验证：template 不能为零地址
└── 设置：self.exchangeTemplate = template
```

#### 1.2 交易所创建
```
createExchange(token)
├── 验证：token 地址有效
├── 验证：工厂已初始化
├── 验证：该代币尚未创建交易所
├── 创建：使用 create_with_code_of 克隆交易所模板
├── 初始化：调用 setup() 设置代币地址和工厂
├── 注册：建立 token ↔ exchange 双向映射
├── 编号：分配唯一 token_id
└── 触发事件：NewExchange(token, exchange)
```

#### 1.3 交易所设置
```
setup(token_addr)
├── 验证：factory 和 token 都为零地址（确保未被初始化）
├── 验证：token_addr 非零
├── 设置：self.factory = msg.sender（工厂地址）
├── 设置：self.token = token_addr（代币地址）
├── 设置：name = "Uniswap V1"
├── 设置：symbol = "UNI-V1"
└── 设置：decimals = 18
```

---

### 二、流动性管理

#### 2.1 添加流动性（初始创建）
```
addLiquidity() - 当 totalSupply == 0 时
├── 验证：deadline 有效
├── 验证：工厂和代币已设置
├── 验证：msg.value >= 1 gwei（防止零流动性创建）
├── 验证：这是该代币的官方交易所
├── 设置：token_amount = max_tokens（用户决定初始价格）
├── 铸造：initial_liquidity = msg.value（UNI 数量 = ETH 数量）
├── 设置：totalSupply = initial_liquidity
├── 转账：从用户转入 token_amount 代币到合约
├── 触发事件：AddLiquidity(provider, eth_amount, token_amount)
└── 返回：initial_liquidity
```

**关键点**：初始流动性提供者确定代币的初始价格（ETH/Token 比例）。

#### 2.2 添加流动性（后续添加）
```
addLiquidity() - 当 totalSupply > 0 时
├── 验证：min_liquidity > 0
├── 计算：eth_reserve = self.balance - msg.value（当前 ETH 储备）
├── 计算：token_reserve = token.balanceOf(self)（当前代币储备）
├── 计算应存入代币数：
│   token_amount = msg.value * token_reserve / eth_reserve + 1
├── 计算应铸造 UNI 数：
│   liquidity_minted = msg.value * totalSupply / eth_reserve
├── 验证：max_tokens >= token_amount（用户接受代币数量）
├── 验证：liquidity_minted >= min_liquidity（用户接受 UNI 数量）
├── 铸造：balances[msg.sender] += liquidity_minted
├── 增加：totalSupply += liquidity_minted
├── 转账：从用户转入 token_amount 代币到合约
├── 触发事件：AddLiquidity(provider, eth_amount, token_amount)
└── 返回：liquidity_minted
```

**关键点**：后续添加流动性必须按当前池比例存入。

#### 2.3 移除流动性
```
removeLiquidity(amount, min_eth, min_tokens, deadline)
├── 验证：amount > 0, deadline 有效, min_eth > 0, min_tokens > 0
├── 验证：totalSupply > 0
├── 计算：token_reserve = token.balanceOf(self)
├── 计算：eth_amount = amount * self.balance / totalSupply
├── 计算：token_amount = amount * token_reserve / totalSupply
├── 验证：eth_amount >= min_eth
├── 验证：token_amount >= min_tokens
├── 销毁：balances[msg.sender] -= amount
├── 减少：totalSupply -= amount
├── 转账：发送 eth_amount ETH 给用户
├── 转账：发送 token_amount 代币给用户
├── 触发事件：RemoveLiquidity(provider, eth_amount, token_amount)
└── 返回：(eth_amount, token_amount)
```

**关键点**：按持有 UNI 比例提取储备资产。

---

### 三、价格计算核心

#### 3.1 输入型定价（Input Price）
当用户指定**输入数量**时，计算能获得多少输出。

```
getInputPrice(input_amount, input_reserve, output_reserve)
├── 验证：input_reserve > 0, output_reserve > 0
├── 计算：input_amount_with_fee = input_amount * 997（扣除 0.3% 手续费）
├── 计算：numerator = input_amount_with_fee * output_reserve
├── 计算：denominator = input_reserve * 1000 + input_amount_with_fee
└── 返回：output_amount = numerator / denominator
```

**公式推导**（恒定乘积 x·y = k）：
```
k = input_reserve * output_reserve
k' = (input_reserve + input_with_fee) * (output_reserve - output_amount)

input_with_fee = input_amount * 997 / 1000

output_amount = output_reserve - k / (input_reserve + input_with_fee)
              = input_with_fee * output_reserve / (input_reserve + input_with_fee)
```

#### 3.2 输出型定价（Output Price）
当用户指定**输出数量**时，计算需要多少输入。

```
getOutputPrice(output_amount, input_reserve, output_reserve)
├── 验证：input_reserve > 0, output_reserve > 0
├── 计算：numerator = input_reserve * output_amount * 1000
├── 计算：denominator = (output_reserve - output_amount) * 997
└── 返回：input_amount = numerator / denominator + 1
```

**公式推导**：
```
k = input_reserve * output_reserve
k' = (input_reserve + input_with_fee) * (output_reserve - output_amount)

input_with_fee = k / (output_reserve - output_amount) - input_reserve
               = input_reserve * output_amount / (output_reserve - output_amount)
input_amount = input_with_fee * 1000 / 997
```

**+1 的作用**：防止除法精度损失导致的滑点攻击。

---

### 四、交易执行

#### 4.1 ETH → Token（指定输入数量）

```
ethToTokenSwapInput(min_tokens, deadline) @payable
├── 调用：ethToTokenInput(msg.value, min_tokens, deadline, msg.sender, msg.sender)
│   ├── 验证：deadline 有效, eth_sold > 0, min_tokens > 0
│   ├── 计算：token_reserve = token.balanceOf(self)
│   ├── 计算：tokens_bought = getInputPrice(msg.value, balance - msg.value, token_reserve)
│   ├── 验证：tokens_bought >= min_tokens
│   ├── 转账：发送 tokens_bought 代币给接收者
│   ├── 触发事件：TokenPurchase(buyer, eth_sold, tokens_bought)
│   └── 返回：tokens_bought
└── 返回：tokens_bought
```

#### 4.2 ETH → Token（指定输出数量）

```
ethToTokenSwapOutput(tokens_bought, deadline) @payable
├── 调用：ethToTokenOutput(tokens_bought, msg.value, deadline, msg.sender, msg.sender)
│   ├── 验证：deadline 有效, tokens_bought > 0, max_eth > 0
│   ├── 计算：token_reserve = token.balanceOf(self)
│   ├── 计算：eth_sold = getOutputPrice(tokens_bought, balance - msg.value, token_reserve)
│   ├── 计算退款：eth_refund = max_eth - eth_sold
│   ├── 如果有退款：发送 eth_refund 给买家
│   ├── 转账：发送 tokens_bought 代币给接收者
│   ├── 触发事件：TokenPurchase(buyer, eth_sold, tokens_bought)
│   └── 返回：eth_sold
└── 返回：eth_sold
```

**关键点**：用户可能发送过多 ETH，多余部分会退还。

#### 4.3 Token → ETH（指定输入数量）

```
tokenToEthSwapInput(tokens_sold, min_eth, deadline)
├── 调用：tokenToEthInput(tokens_sold, min_eth, deadline, msg.sender, msg.sender)
│   ├── 验证：deadline 有效, tokens_sold > 0, min_eth > 0
│   ├── 计算：token_reserve = token.balanceOf(self)
│   ├── 计算：eth_bought = getInputPrice(tokens_sold, token_reserve, balance)
│   ├── 验证：eth_bought >= min_eth
│   ├── 转账：发送 eth_bought ETH 给接收者
│   ├── 转账：从用户转入 tokens_sold 代币到合约
│   ├── 触发事件：EthPurchase(buyer, tokens_sold, eth_bought)
│   └── 返回：eth_bought
└── 返回：eth_bought
```

#### 4.4 Token → Token（通过 ETH 中继）

```
tokenToTokenSwapInput(tokens_sold, min_tokens_bought, min_eth_bought, deadline, token_addr)
├── 获取目标交易所：exchange_addr = factory.getExchange(token_addr)
├── 调用：tokenToTokenInput(..., exchange_addr)
│   ├── 验证：exchange_addr != self, exchange_addr != ZERO_ADDRESS
│   ├── 计算：token_reserve = token.balanceOf(self)
│   ├── 计算：eth_bought = getInputPrice(tokens_sold, token_reserve, balance)
│   ├── 验证：eth_bought >= min_eth_bought
│   ├── 转账：从用户转入 tokens_sold 代币到当前合约
│   ├── 调用目标交易所：
│   │   Exchange(exchange_addr).ethToTokenTransferInput(min_tokens_bought, deadline, recipient, value=eth_bought)
│   ├── 触发事件：EthPurchase(buyer, tokens_sold, eth_bought)
│   └── 返回：tokens_bought
└── 返回：tokens_bought
```

**流程**：
```
Token A → [Exchange A] → ETH → [Exchange B] → Token B
```

---

### 五、价格查询

| 函数                                      | 用途                          | 返回值           |
| ----------------------------------------- | ----------------------------- | ---------------- |
| `getEthToTokenInputPrice(eth_sold)`       | 查询固定 ETH 能买多少代币     | tokens_bought    |
| `getEthToTokenOutputPrice(tokens_bought)` | 查询购买固定代币需要多少 ETH  | eth_sold (wei)   |
| `getTokenToEthInputPrice(tokens_sold)`    | 查询固定代币能买多少 ETH      | eth_bought (wei) |
| `getTokenToEthOutputPrice(eth_bought)`    | 查询购买固定 ETH 需要多少代币 | tokens_sold      |

这些函数不改变状态，仅用于价格预览和前端展示。

---

### 六、ERC20 流动性代币

Exchange 合约的流动性凭证（UNI-V1）实现了完整的 ERC20 标准：

| 函数                               | 功能             |
| ---------------------------------- | ---------------- |
| `balanceOf(_owner)`                | 查询 UNI 余额    |
| `transfer(_to, _value)`            | 转让 UNI         |
| `transferFrom(_from, _to, _value)` | 授权转让 UNI     |
| `approve(_spender, _value)`        | 授权他人使用 UNI |
| `allowance(_owner, _spender)`      | 查询授权额度     |

**用途**：
- 流动性提供者可以转让、出售其流动性份额
- 支持 DeFi 协议集成（如抵押借贷）

---

## 使用场景

### 场景 1：新代币上市

```
1. 代币团队调用 Factory.createExchange(token)
   └── 部署该代币专属的 Exchange 合约

2. 代币团队调用 Exchange.addLiquidity(0, max_tokens, deadline)
   └── 存入初始 ETH 和代币，确定初始价格
   └── 获得初始 UNI-V1 流动性代币
```

### 场景 2：用户购买代币

```
选项 A（指定 ETH 数量）：
用户发送 ETH 到 Exchange 地址
└── 自动调用 __default__()
    └── ethToTokenSwapInput(1, block.timestamp)
        └── 按当前价格获得代币

选项 B（指定代币数量）：
用户调用 ethToTokenSwapOutput(tokens_bought, deadline)
├── 发送 msg.value ETH（可以过量）
├── 合约计算所需 ETH
└── 退还多余的 ETH
```

### 场景 3：用户出售代币

```
用户先授权：token.approve(exchange_address, amount)

然后调用：tokenToEthSwapInput(tokens_sold, min_eth, deadline)
├── 转入代币到合约
└── 获得 ETH
```

### 场景 4：代币互换

```
用户想要用 Token A 换取 Token B：
├── 授权 Exchange A 使用 Token A
└── 调用 Exchange A.tokenToTokenSwapInput(tokens_sold, ..., token_B_address)
    ├── Token A → ETH（在 Exchange A）
    └── ETH → Token B（在 Exchange B）
```

### 场景 5：流动性管理

```
添加流动性：
├── 授权 Exchange 使用代币
└── 调用 addLiquidity(min_liquidity, max_tokens, deadline)

移除流动性：
└── 调用 removeLiquidity(amount, min_eth, min_tokens, deadline)
    ├── 销毁 UNI-V1
    └── 提取 ETH 和代币

转让流动性：
└── 调用 transfer() 转让 UNI-V1 给其他人
```

---

## 关键设计决策

### 1. 每个代币一个交易所
- **优点**：隔离风险，一个代币出问题不影响其他
- **缺点**：Gas 成本较高（需部署多个合约）

### 2. 恒定乘积公式（x·y = k）
- **优点**：无需做市商，自动定价，流动性始终可用
- **缺点**：大额交易滑点明显

### 3. 0.3% 交易手续费
- 体现在定价公式中的 997/1000 比例
- 手续费留在池中，增加流动性提供者收益

### 4. UNI-V1 作为流动性凭证
- 流动性提供者获得可交易的代币
- 支持流动性二级市场

### 5. 两阶段定价（Input/Output）
- **Input**：用户控制输入，获得可变输出
- **Output**：用户控制输出，支付可变输入
- 满足不同交易策略需求

---

## 数据流图

```
┌─────────────────┐
│   Factory       │
│ (创建交易所)     │
└────────┬────────┘
         │ createExchange(token)
         ▼
┌─────────────────┐         ┌─────────────────┐
│  Exchange A     │         │  Exchange B     │
│  (Token A ↔ ETH)│         │  (Token B ↔ ETH)│
└────────┬────────┘         └────────┬────────┘
         │                            │
         │ addLiquidity()             │ addLiquidity()
         ▼                            ▼
┌─────────────────┐         ┌─────────────────┐
│  流动性池 A      │         │  流动性池 B      │
│  ETH + Token A  │         │  ETH + Token B  │
└─────────────────┘         └─────────────────┘
         ▲                            ▲
         │ tokenToTokenSwapInput()    │
         │────────────────────────────┘
         │   (通过 ETH 中继)
         │
┌─────────────────┐
│     用户        │
└─────────────────┘
```

---

## 安全注意事项

### 1. 滑点保护
- 所有交易函数都支持设置最小输出（`min_tokens`, `min_eth`）
- 防止交易期间价格剧烈变动导致的损失

### 2. 截止时间
- 所有交易都有 `deadline` 参数
- 防止交易在内存池中被挟持

### 3. 重新入攻击防护
- 使用 Checks-Effects-Interacts 模式
- 先更新状态，再进行外部调用

### 4. 整数溢出
- Vyper 默认开启溢出检查
- 0.3% 手续费使用 997/1000 避免浮点数运算

---

## 总结

Uniswap V1 的核心创新在于：
1. **自动化做市商**：无需订单簿，恒定乘积公式自动定价
2. **流动性激励**：UNI-V1 代币将流动性转化为可交易资产
3. **去中心化**：任何人都可以添加流动性或进行交易
4. **可组合性**：ERC20 标准的流动性代币支持 DeFi 集成

这种设计为后续 Uniswap V2、V3 以及整个 AMM 领域奠定了基础。