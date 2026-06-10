contract Exchange():
    def setup(token_addr: address): modifying

# NewExchange: event({token: indexed(address), exchange: indexed(address)})  # 新交易所事件：记录新创建的代币和交易所地址
NewExchange: event({token: indexed(address), exchange: indexed(address)})

exchangeTemplate: public(address)
tokenCount: public(uint256)
token_to_exchange: address[address]
exchange_to_token: address[address]
id_to_token: address[uint256]

@public
# def initializeFactory(template: address):  # 初始化工厂，设置交易所模板
def initializeFactory(template: address):
    assert self.exchangeTemplate == ZERO_ADDRESS
    assert template != ZERO_ADDRESS
    self.exchangeTemplate = template

@public
# def createExchange(token: address) -> address:  # 为指定代币创建新的交易所合约
def createExchange(token: address) -> address:
    assert token != ZERO_ADDRESS
    assert self.exchangeTemplate != ZERO_ADDRESS
    assert self.token_to_exchange[token] == ZERO_ADDRESS
    exchange: address = create_with_code_of(self.exchangeTemplate)
    Exchange(exchange).setup(token)
    self.token_to_exchange[token] = exchange
    self.exchange_to_token[exchange] = token
    token_id: uint256 = self.tokenCount + 1
    self.tokenCount = token_id
    self.id_to_token[token_id] = token
    log.NewExchange(token, exchange)
    return exchange

@public
@constant
# def getExchange(token: address) -> address:  # 获取指定代币的交易所地址
def getExchange(token: address) -> address:
    return self.token_to_exchange[token]

@public
@constant
# def getToken(exchange: address) -> address:  # 获取指定交易所对应的代币地址
def getToken(exchange: address) -> address:
    return self.exchange_to_token[exchange]

@public
@constant
# def getTokenWithId(token_id: uint256) -> address:  # 根据代币ID获取代币地址
def getTokenWithId(token_id: uint256) -> address:
    return self.id_to_token[token_id]
