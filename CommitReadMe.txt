## Fixing the Test/forking/CrossChainTest.t.sol
### The problems
####testBridgeAllTokensBack()
##### First problem
"Not Enough Permission" Error (allowance exceeded)
the main cause for this problem was of refactor we did to the logic function
to free the slot and fix via-ir problem we make us call get fee two time 
-> fixed but allowance tobe type(uint96).max and ask for more SEPOLIA_LINK_ADDRESS
#### Second problem "Empty Wallet" Error (InsufficientBalance)
-> the test senario was to send back but send in was in diff function
my mistake i forgot about foundry test setUp() then test then forget 
-> since we only deploying vault on sepolia i can mint him token
-> fixed by combining the logic of pervs function with second function
#### Third problem "fork selction" 
because we add some assert to the new function test 
and manage forge selection
we had to change logic functions to be able to meet there fork network needs