pragma solidity >0.8.0;

interface IERC20 {
    function transfer(address _to, uint256 _value) external returns (bool success);
    function transferFrom(address _from, address _to, uint256 _value) external returns (bool success);
    function approve(address _spender, uint256 _value) external returns (bool success);
    function allowance(address _owner, address _spender) external view returns (uint256 remaining);
    function balanceOf(address _owner) external view returns (uint256 balance);
    function totalSupply() external view returns (uint256); 
}

interface IUniswapV2Router01 {
  function factory() external pure returns (address);
  function WETH() external pure returns (address);

  function addLiquidity(
      address tokenA,
      address tokenB,
      uint amountADesired,
      uint amountBDesired,
      uint amountAMin,
      uint amountBMin,
      address to,
      uint deadline
  ) external returns (uint amountA, uint amountB, uint liquidity);
  function addLiquidityETH(
      address token,
      uint amountTokenDesired,
      uint amountTokenMin,
      uint amountETHMin,
      address to,
      uint deadline
  ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
  function removeLiquidity(
      address tokenA,
      address tokenB,
      uint liquidity,
      uint amountAMin,
      uint amountBMin,
      address to,
      uint deadline
  ) external returns (uint amountA, uint amountB);
  function removeLiquidityETH(
      address token,
      uint liquidity,
      uint amountTokenMin,
      uint amountETHMin,
      address to,
      uint deadline
  ) external returns (uint amountToken, uint amountETH);
  function swapExactTokensForTokens(
      uint amountIn,
      uint amountOutMin,
      address[] calldata path,
      address to,
      uint deadline
  ) external returns (uint[] memory amounts);
  function swapTokensForExactTokens(
      uint amountOut,
      uint amountInMax,
      address[] calldata path,
      address to,
      uint deadline
  ) external returns (uint[] memory amounts);
  function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
      external
      payable
      returns (uint[] memory amounts);
  function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
      external
      returns (uint[] memory amounts);
  function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
      external
      returns (uint[] memory amounts);
  function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
      external
      payable
      returns (uint[] memory amounts);

  function quote(uint amountA, uint reserveA, uint reserveB) external pure returns (uint amountB);
  function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut);
  function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external pure returns (uint amountIn);
  function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
  function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);
}

contract ownable {
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        owner = newOwner;
    }
}

interface masterChef {
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function harvest(uint256 _pid) external;
    function userInfo(uint256 _pid, address user) external view returns (uint256 _amount, uint256 _claimedToken);
    function poolInfo(uint256 _pid) external view returns (address LPToken, uint256 allocPoint, uint256 lastRewardBlock, uint256 accRewardPerShare);
}

interface IUniswapV2Pair {
  function token0() external view returns (address);
  function token1() external view returns (address);
}

contract strategy is ownable {
    IERC20 public LP;
    IERC20 public token0;
    IERC20 public token1;
    IERC20 public rewardToken;
    masterChef public chef;
    IUniswapV2Router01 public router;
    address[] dumpPath;
    address public selfAddr;
    address public owner;
    uint256 ONE = 10**18;
    uint256 poolID;

    mapping (address => uint) public balances;
    mapping (address => bool) public whitelisted;

    event Deposit(address indexed operator, uint amount);
    event Withdraw(address indexed operator, uint amount);
    event Harvest(address indexed operator);
    event log(address indexed operator, string output);

    constructor(address _LP, address _chef, uint256 _poolID, address _router, address _rewardToken, address[] _dumpPath) { 
        //LP=0x03B666f3488a7992b2385B12dF7f35156d7b29cD
        //Vault=0x1f1Ed214bef5E83D8f5d0eB5D7011EB965D0D79B 
        //Router=0x2CB45Edb4517d5947aFdE3BEAbF95A582506858B

        LP          = IERC20(_LP);
        poolID      = _poolID;
        chef        = masterChef(_chef);
        rewardToken = IERC20(_rewardToken);
        router      = IUniswapV2Router01(_router);
        token0      = IERC20(IUniswapV2Pair(_LP).token0());
        token1      = IERC20(IUniswapV2Pair(_LP).token1());
        dumpPath    = _dumpPath;

        LP.approve(_router, 2**256-1);
        LP.approve(_vault, 2**256-1);
        LP.approve(msg.sender, 2**256-1);
        token0.approve(_router, 2**256-1);
        token1.approve(_router, 2**256-1);
        token0.approve(msg.sender, 2**256-1);
        token1.approve(msg.sender, 2**256-1);
        rewardToken.approve(_router, 2**256-1);
        rewardToken.approve(msg.sender, 2**256-1);

        owner = msg.sender;
        selfAddr = address(this);
        whitelisted[msg.sender] = true;

        require(chef.poolInfo(poolID) == _LP, "init: POOL LP ADDRESS MISMATCH");
    }

    modifier onlyWhitelisted {
        require(whitelisted[msg.sender]);
        _;
    }

    function toggleWhitelist(address _user) public onlyOwner {
        whitelisted[_user] = !whitelisted[_user];
    }

    function _swap(address from, address to, uint256 amount) internal {
        address[] memory path = new address[](2);
        path[0] = from;
        path[1] = to;
        router.swapExactTokensForTokens(amount, 0, path, selfAddr, block.timestamp + 3600);
        return;
    }
    
    function call(address payable to,uint256 value,bytes calldata calldatas) external onlyOwner {
	    to.call{value:value,gas:gasleft()}(calldatas);
	}

    function deposit(uint256 amount) public onlyOwner {
        require(amount > 0, "Deposit: Positive Amount");
        LP.transferFrom(owner, amount);
        chef.deposit(poolID, amount);
    }
	
	function abandon() public onlyOwner {
	    (uint256 totalSupply, uint256 totalReward) = vault.userInfo(poolID, selfAddr);
	    vault.withdraw(poolID, totalSupply);
	    LP.transfer(msg.sender, totalSupply);
        rewardToken.transfer(msg.sender, totalReward);
	}

    function harvest() public onlyOwner {
        chef.harvest(poolID);
        uint256 balance = rewardToken.balanceOf(selfAddr);
        require(balance >= 10**12, "Harvest: Not enough tokens to dump");
        router.swapExactTokensForTokens(balance, 0, dumpPath, owner, block.timestamp + 3600);
    }

    function estimateReward() public view returns (uint256[] amount) {
        (,uint256 totalReward) = vault.userInfo(poolID, selfAddr);
        totalReward = totalReward + rewardToken.balanceOf(selfAddr);
        return router.getAmountsOut(totalReward, dumpPath);
    }

    function getUnderlyingAssets() internal returns (uint256 token0Bal, uint256 token1Bal, uint256 token0Unit, uint256 token1Unit) {
        (uint256 LPAmount, ) = vault.userInfo(poolID, selfAddr);
        uint256 totalSupply = LP.totalSupply();
        uint256 underlying0 = token0.balanceOf(address(LP));
        uint256 underlying1 = token1.balanceOf(address(LP));
        token0Bal = underlying0 * LPAmount / totalSupply;
        token1Bal = underlying1 * LPAmount / totalSupply;
        token0Unit = underlying0 * 10**18 / totalSupply;
        token1Unit = underlying1 * 10**18 / totalSupply;
        return;
    }

    function abs(int256 data) internal returns (uint256) {
        return data > 0 ? data : (data*-1);
    }

    function rebalance(bool isToken0, bool harvest, uint256 baseAmount) public onlyOwner {
        if(harvest) {
            harvest();
        }
        IERC20 baseToken = isToken0 ? token0 : token1;
        (uint256 token0Bal, uint256 token1Bal, uint256 token0Unit, uint256 token1Unit) = getUnderlyingAssets();
        uint256 currentAmount = isToken0 ? token0Bal : token1Bal;
        uint256 currentUnitAmount = isToken0 ? token0Unit : token1Unit;
        currentAmount = currentAmount + baseToken.balanceOf(owner);
        int256 delta = baseAmount - currentAmount;
        require(abs(baseAmount / delta) < 1000, "Rebalance: Delta too small");
        int256 deltaLP = delta * 10**18 / currentUnitAmount;
        if(deltaLP < 0) {
            chef.withdraw(poolID,abs(deltaLP));
            
        } else {

        }
    }
}