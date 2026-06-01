import re

PASSWORD_POLICY_ERROR = "密码至少 8 位，并需包含字母和数字。"


def is_password_policy_valid(password: str) -> bool:
    value = password.strip()
    if len(value) < 8:
        return False
    return bool(re.search(r"[A-Za-z]", value)) and bool(re.search(r"\d", value))


def validate_password_policy(password: str) -> str:
    value = password.strip()
    if not is_password_policy_valid(value):
        raise ValueError(PASSWORD_POLICY_ERROR)
    return value
