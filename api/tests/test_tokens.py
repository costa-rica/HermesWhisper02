from app.services.tokens import issue_token, verify_token


def test_token_round_trip() -> None:
    secret = "test-secret-with-at-least-32-bytes"
    token = issue_token("user-1", "nrodrig1@gmail.com", secret, 60)

    claims = verify_token(token, secret)

    assert claims.sub == "user-1"
    assert claims.email == "nrodrig1@gmail.com"
