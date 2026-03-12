import hashlib
import json
import logging
import os
from pathlib import Path
from web3 import Web3
from app.config import settings

logger = logging.getLogger(__name__)

w3 = Web3(Web3.HTTPProvider(settings.ALCHEMY_RPC))

_ABI_PATH = Path(__file__).parent.parent.parent / "blockchain_abi.json"

_contract = None

def _load_contract():
    global _contract
    if _contract is not None:
        return _contract
    if not _ABI_PATH.exists():
        logger.warning("blockchain_abi.json not found — blockchain features disabled")
        return None
    try:
        with open(_ABI_PATH) as f:
            abi = json.load(f)
        checksum_addr = Web3.to_checksum_address(settings.CONTRACT_ADDRESS)
        _contract = w3.eth.contract(address=checksum_addr, abi=abi)
        return _contract
    except Exception as e:
        logger.error(f"Failed to load blockchain contract: {e}")
        return None


def hash_call_record(
    transcript: str, caller_number: str, timestamp: str, category: str
) -> str:
    combined = f"{transcript}|{caller_number}|{timestamp}|{category}"
    return "0x" + hashlib.sha256(combined.encode()).hexdigest()


async def write_to_blockchain(
    call_hash: str, user_id: str, category: str, is_scam: bool
) -> str:
    contract = _load_contract()
    if not contract:
        logger.warning("Blockchain write skipped — contract not loaded")
        return ""

    if not w3.is_connected():
        logger.warning("Web3 not connected — blockchain write skipped")
        return ""

    try:
        account = w3.eth.account.from_key(settings.DEPLOYER_PRIVATE_KEY)
        nonce = w3.eth.get_transaction_count(account.address)

        tx = contract.functions.recordCall(
            call_hash,
            user_id,
            category,
            is_scam,
        ).build_transaction(
            {
                "from": account.address,
                "nonce": nonce,
                "gas": 200000,
                "gasPrice": w3.eth.gas_price,
            }
        )

        signed = w3.eth.account.sign_transaction(tx, settings.DEPLOYER_PRIVATE_KEY)
        tx_hash = w3.eth.send_raw_transaction(signed.raw_transaction)
        receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=60)
        tx_hash_hex = receipt.transactionHash.hex()
        logger.info(f"Blockchain tx recorded: {tx_hash_hex}")
        return tx_hash_hex
    except Exception as e:
        logger.error(f"Blockchain write failed: {e}")
        return ""


def verify_on_chain(call_hash: str) -> bool:
    contract = _load_contract()
    if not contract:
        return False
    if not w3.is_connected():
        return False

    try:
        result = contract.functions.verifyCall(call_hash).call()
        return bool(result)
    except Exception as e:
        logger.error(f"Blockchain verify failed: {e}")
        return False