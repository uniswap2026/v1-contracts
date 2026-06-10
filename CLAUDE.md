# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概览

这是 Uniswap V1 的合约仓库,使用 Vyper 语言编写。Uniswap V1 是一个去中心化交易协议,由两个主要合约组成:
- **Factory 合约** (`uniswap_factory.vy`): 用于创建和管理 ERC20 token 的交换合约
- **Exchange 合约** (`uniswap_exchange.vy`): 用于实际执行 ETH 和 ERC20 token 之间的交换

该仓库使用 Vyper 0.1.0b4 版本编写,这是 Uniswap V1 最初使用的版本。

## 开发环境设置

### 依赖安装

项目需要 Python 3 环境。安装步骤:

1. 创建虚拟环境:
```bash
pip3 install virtualenv
virtualenv -p python3 env
source env/bin/activate
```

2. 安装依赖:
```bash
pip install -r requirements.txt
```

### (可选) 切换 Vyper 编译器版本

如果需要使用与 Uniswap 验证相同的 Vyper 版本:
```bash
cd vyper
git reset --hard 35038d20bd9946a35261c4c4fbcb27fe61e65f78
cd ..
```

## 测试

### 运行所有测试
```bash
pytest -v tests/
```

### 运行特定测试文件
```bash
pytest -v tests/exchange/test_ERC20.py
pytest -v tests/exchange/test_eth_to_token.py
pytest -v tests/exchange/test_token_to_eth.py
pytest -v tests/exchange/test_token_to_token.py
pytest -v tests/exchange/test_token_to_exchange.py
pytest -v tests/exchange/test_factory.py
pytest -v tests/exchange/test_liquidity_pool.py
```

## 合约架构

### Factory 合约 (`uniswap_factory.vy`)

Factory 合约负责:
- 初始化交换合约模板
- 为每个 ERC20 token 创建独立的交换合约
- 维护 token 地址到交换合约地址的映射

关键函数:
- `initializeFactory(template)`: 初始化工厂,设置交换合约模板
- `createExchange(token)`: 为指定 token 创建新的交换合约
- `getExchange(token)`: 获取指定 token 的交换合约地址

### Exchange 合约 (`uniswap_exchange.vy`)

每个 Exchange 合约都是独立部署的,专门处理一种 ERC20 token 和 ETH 之间的交换。

核心机制:
1. **流动性池**: 用户提供 ETH 和 token 成对存入,获得 UNI-V1 流动性代币
2. **自动做市商 (AMM)**: 使用恒定乘积公式 (x * y = k) 进行价格确定
3. **手续费**: 每笔交易收取 0.3% 手续费 (体现在 997/1000 的比例中)

主要功能模块:

**流动性管理**:
- `addLiquidity()`: 添加流动性,提供 ETH 和 token
- `removeLiquidity()`: 移除流动性,赎回 ETH 和 token

**交易功能**:
- `ethToTokenSwapInput/TransferInput()`: 用固定 ETH 数量交换 token
- `ethToTokenSwapOutput/TransferOutput()`: 用最多 ETH 数量交换固定 token 数量
- `tokenToEthSwapInput/TransferInput()`: 用固定 token 数量交换 ETH
- `tokenToEthSwapOutput/TransferOutput()`: 用最多 token 数量交换固定 ETH 数量
- `tokenToTokenSwapInput/TransferInput()`: 通过 ETH 中继进行 token-to-token 交换
- `tokenToTokenSwapOutput/TransferOutput()`: 通过 ETH 中继进行 token-to-token 交换(指定输出)

**价格查询**:
- `getEthToTokenInputPrice()`: 查询用固定 ETH 能换取多少 token
- `getEthToTokenOutputPrice()`: 查询换取固定 token 需要多少 ETH
- `getTokenToEthInputPrice()`: 查询用固定 token 能换取多少 ETH
- `getTokenToEthOutputPrice()`: 查询换取固定 ETH 需要多少 token

**ERC20 功能**:
- Exchange 合约的流动性代币 (UNI-V1) 实现了 ERC20 标准,可以转让和授权

### 测试合约 (`test_contracts/ERC20.vy`)

这是一个用于测试的通用 ERC20 token 合约,不参与实际部署。

## 定价公式

项目使用恒定乘积 AMM 公式,带有 0.3% 交易手续费:

**输入型交换 (Input Price)**:
```
output_amount = input_amount * 0.997 * output_reserve / (input_reserve * 1000 + input_amount * 0.997)
```

**输出型交换 (Output Price)**:
```
input_amount = input_reserve * output_amount * 1000 / ((output_reserve - output_amount) * 0.997) + 1
```

其中:
- `input_reserve`: 输入资产在池中的储备量
- `output_reserve`: 输出资产在池中的储备量
- `0.997`: 1 - 0.003 (0.3% 手续费)

## 测试框架

测试使用 pytest 和 eth-tester (PyEVMBackend)。主要 fixtures (在 `tests/conftest.py` 中):

- `w3`: Web3 实例,连接到测试链
- `factory`: 已初始化的 Factory 合约实例
- `exchange_template`: Exchange 合约模板
- `HAY_token` / `DEN_token`: 测试用的 ERC20 token
- `HAY_exchange` / `DEN_exchange`: 已部署并添加流动性的交换合约
- `swap_input` / `swap_output`: 定价计算辅助函数

## 文件结构

```
.
├── abi/                    # 合约 ABI 文件
├── bytecode/               # 合约字节码文件
├── contracts/
│   ├── uniswap_factory.vy  # Factory 合约源码
│   ├── uniswap_exchange.vy # Exchange 合约源码
│   └── test_contracts/
│       └── ERC20.vy        # 测试用 ERC20 token 合约
└── tests/
    ├── conftest.py         # pytest fixtures 和测试配置
    ├── constants.py        # 测试常量
    └── exchange/           # 功能测试文件
```