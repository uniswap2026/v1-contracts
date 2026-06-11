# Uniswap V1 收益说明

Exchange 合约记录的是：

```solidity
mapping(address => uint256) balances;
uint256 totalSupply;
```

即：

* LP余额
* LP总量

销毁（移除流动性）时计算：

```text
ETH_out = LP_burn * ETH_reserve / LP_total

Token_out = LP_burn * Token_reserve / LP_total
```

也就是说：**LP 的价值取决于当前池子的储备量。**

## 举个例子

### Alice 与 Bob 的初始状态（t=0）

Alice 创建池子：

* 100 ETH
* 10000 ABC

获得：100 LP

Bob 后来加入：

* 100 ETH
* 10000 ABC

获得：100 LP

此时，双方各占：100 / 200 = 50% LP

| 项目     | ETH | ABC   | LP  | LP 占比     |
| -------- | --- | ----- | --- | ----------- |
| Alice LP | 100 | 10000 | 100 | 100/200=50% |
| Bob LP   | 100 | 10000 | 100 | 100/200=50% |
| LP总量   | 200 | 20000 | 200 |             |

### 有人来 Swap 了，产生手续费（t=1）

手续费累计后：

池子变成：

* 220 ETH
* 22000 ABC

LP总量仍然：200 LP

### Alice 移除流动性（t=2）

Alice销毁：100 LP

得到：

```text
ETH_out = LP_burn * ETH_reserve / LP_total
        = 100 * 220 / 200
        = 110 ETH

Token_out = LP_burn * Token_reserve / LP_total
          = 100 * 22000 / 200
          = 11000 ABC
```

收益来自：**池子储备增长。**

## 收益本质

手续费立即加入储备池（liquidity reserves），不会增发新的 LP Token，因此所有 LP Token 的价值自动增加。

LP Token 在销毁（移除流动性）时领取这些累计手续费。

因此：

```text
创建池子
    ↓
获得 LP Token

用户 Swap
    ↓
0.3% 手续费进入池子

池子储备增加
    ↓
LP Token 数量不变

每个 LP Token 对应的资产增多
    ↓
移除流动性时一次性领取
```

Exchange 记录了LP数量与LP总量，百分比 = LP数量 / LP总量。

手续费进入池子后，LP总量不变而池子资产变多，所以每个 LP Token 更值钱，LP 获得收益。
