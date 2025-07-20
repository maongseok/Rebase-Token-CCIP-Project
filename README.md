# Cross-Chain Rebase Token

 1. A protocol that allows user to deposit into a vault and in return, receiver rebase tokens that represent their underlying balance
 2. Tebase toke -> balanceOf function is dynamic  to show the changing balance with time.
    - Balance increases linearly with time
    - mint tokens to our users every time they perform an action (minting, burning, transferring, or.... bridging)
 3. Interest rate
    - Indivually set an interest rate or each user based on some global interest rate of the protocol at the time the user deposits into the vault.
    - This global interest rate can only decrease to incetivise\reward early adopters.
    - increase token adoption

# Those Are the Address In TEST Net ZKsync and sepoliaETH

SEPOLIA_POOL_ADDRESS="0xfF6772ac8c69F8742519F722Cb9eba7836e496Fd"
ZKSYNC_POOL_ADDRESS="0xFE80823600CA94d77ed7963996237622452cC474"
ZKSYNC_REBASE_TOKEN_ADDRESS="0xF1f77DA35D399a3d88759f3dAd12aE1E89e11259"
SEPOLIA_REBASE_TOKEN_ADDRESS="0x5ea42735cB3e7553f28F351f564686929de512BB"
