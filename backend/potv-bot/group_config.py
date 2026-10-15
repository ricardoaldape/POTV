"""Public bot/group routing. Secrets and mutable deployment values come from env."""
import os

GROUP_CHAT_ID = os.getenv("POTV_GROUP_CHAT_ID", "").strip()
GROUP_INVITE_URL = os.getenv("POTV_GROUP_INVITE_URL", "").strip()
BOT_PUBLIC_URL = os.getenv(
    "POTV_BOT_PUBLIC_URL", "https://t.me/potvoficialbot"
).strip()
