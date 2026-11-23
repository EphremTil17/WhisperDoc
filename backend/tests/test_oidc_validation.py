"""OIDC token validation against a faked identity provider.

Tokens are signed with locally generated RSA keys and verified by the real
auth.oidc code; only the IdP's HTTP endpoints (discovery, JWKS) are faked.
"""

import pytest

from auth import oidc, validate_token
from tests.fakes import (
    CLIENT_ID,
    DISCOVERED_ISSUER,
    ISSUER,
    JWKS_URI,
    KID,
    FakeIdP,
    clear_oidc_caches,
    install_idp,
    make_token,
    new_rsa_key,
    private_jwk,
    public_jwk,
)


@pytest.fixture(scope="module")
def signing_key():
    return new_rsa_key()


@pytest.fixture(scope="module")
def other_key():
    return new_rsa_key()


@pytest.fixture
def idp(signing_key):
    return FakeIdP(jwks={"keys": [public_jwk(signing_key, KID)]})


@pytest.fixture
def clock(monkeypatch, idp):
    clock = install_idp(monkeypatch, idp)
    yield clock
    clear_oidc_caches()


# ---------------------------------------------------------------------------
# Accepting and rejecting tokens
# ---------------------------------------------------------------------------


def test_valid_token_returns_its_claims(clock, idp, signing_key):
    token = make_token(signing_key, sub="alice", email="alice@example.test")

    payload = oidc.validate_oidc_token(token)

    assert payload is not None
    assert payload["sub"] == "alice"
    assert payload["email"] == "alice@example.test"
    assert idp.fetched == [
        f"{DISCOVERED_ISSUER}/.well-known/openid-configuration",
        JWKS_URI,
    ]


def test_dual_door_validator_accepts_a_jwt(clock, signing_key):
    assert validate_token(make_token(signing_key)) is True
    assert validate_token(make_token(signing_key, aud="someone-else")) is False


def test_discovery_and_jwks_are_cached_between_validations(clock, idp, signing_key):
    for sub in ("a", "b", "c"):
        payload = oidc.validate_oidc_token(make_token(signing_key, sub=sub))
        assert payload is not None and payload["sub"] == sub

    assert idp.discovery_fetches == 1
    assert idp.jwks_fetches == 1


@pytest.mark.parametrize(
    "claims",
    [
        pytest.param(
            {"iss": "https://evil.example.test/application/o/whisperdoc"},
            id="foreign-issuer",
        ),
        pytest.param({"iss": DISCOVERED_ISSUER + "-staging"}, id="sibling-issuer"),
        pytest.param({"aud": "another-client"}, id="wrong-audience"),
        pytest.param({"exp_in": -60}, id="expired"),
        pytest.param({"nbf_in": 120}, id="not-yet-valid"),
    ],
)
def test_tokens_with_bad_claims_are_rejected(clock, signing_key, claims):
    assert oidc.validate_oidc_token(make_token(signing_key, **claims)) is None


def test_expiry_allows_ten_seconds_of_clock_skew(clock, signing_key):
    assert oidc.validate_oidc_token(make_token(signing_key, exp_in=-5)) is not None
    assert oidc.validate_oidc_token(make_token(signing_key, exp_in=-15)) is None


def test_multi_audience_token_containing_the_client_id_is_accepted(clock, signing_key):
    token = make_token(signing_key, aud=["https://other.api", CLIENT_ID])
    assert oidc.validate_oidc_token(token) is not None


def test_api_resource_is_the_audience_when_no_client_id_is_set(
    monkeypatch, clock, signing_key
):
    monkeypatch.setattr(oidc, "OIDC_CLIENT_ID", "")
    monkeypatch.setattr(oidc, "OIDC_API_RESOURCE", "https://api.whisperdoc.test")

    assert (
        oidc.validate_oidc_token(
            make_token(signing_key, aud="https://api.whisperdoc.test")
        )
        is not None
    )
    assert oidc.validate_oidc_token(make_token(signing_key, aud=CLIENT_ID)) is None


def test_token_signed_by_an_untrusted_key_is_rejected(clock, other_key):
    # Correct kid and claims, but the signature is not from the IdP's key.
    assert oidc.validate_oidc_token(make_token(other_key)) is None


@pytest.mark.parametrize("algorithm", ["RS384", "RS512", "PS256"])
def test_only_rs256_is_accepted_even_with_the_right_key(clock, signing_key, algorithm):
    assert (
        oidc.validate_oidc_token(make_token(signing_key, algorithm=algorithm)) is None
    )


def test_hs256_token_keyed_with_the_public_jwk_is_rejected(clock, signing_key):
    secret = public_jwk(signing_key, KID)["n"].encode() * 2
    token = make_token(secret, algorithm="HS256")
    assert oidc.validate_oidc_token(token) is None


def test_garbage_token_is_rejected_without_crashing(clock):
    assert oidc.validate_oidc_token("not-a-jwt") is None
    assert oidc.validate_oidc_token("a.b.c") is None


def test_token_without_kid_is_rejected_without_refetching(clock, idp, signing_key):
    assert oidc.validate_oidc_token(make_token(signing_key, kid=None)) is None
    assert idp.jwks_fetches == 1


# ---------------------------------------------------------------------------
# Key rotation: unknown kid triggers one rate-limited JWKS refetch
# ---------------------------------------------------------------------------


def test_rotated_key_is_picked_up_by_one_refetch(clock, idp, signing_key, other_key):
    assert oidc.validate_oidc_token(make_token(signing_key)) is not None
    # The IdP rotates in a new key after our JWKS was cached.
    idp.jwks = {
        "keys": [public_jwk(signing_key, KID), public_jwk(other_key, "rotated")]
    }

    payload = oidc.validate_oidc_token(make_token(other_key, kid="rotated", sub="bob"))

    assert payload is not None and payload["sub"] == "bob"
    assert idp.jwks_fetches == 2
    # The refreshed JWKS is cached: the rotated key now validates offline.
    assert oidc.validate_oidc_token(make_token(other_key, kid="rotated")) is not None
    assert idp.jwks_fetches == 2


def test_unknown_kids_refetch_at_most_once_per_cooldown(clock, idp, signing_key):
    for i in range(5):
        assert (
            oidc.validate_oidc_token(make_token(signing_key, kid=f"forged-{i}")) is None
        )
    assert idp.jwks_fetches == 2  # initial fetch + one refetch

    clock.advance(59)
    assert oidc.validate_oidc_token(make_token(signing_key, kid="forged-x")) is None
    assert idp.jwks_fetches == 2

    clock.advance(1)  # exactly one cooldown later: allowed again
    assert oidc.validate_oidc_token(make_token(signing_key, kid="forged-y")) is None
    assert idp.jwks_fetches == 3


# ---------------------------------------------------------------------------
# Hostile or broken JWKS entries fail closed
# ---------------------------------------------------------------------------


def test_private_key_published_in_jwks_is_refused(clock, idp, signing_key):
    idp.jwks = {"keys": [private_jwk(signing_key, KID)]}
    assert oidc.validate_oidc_token(make_token(signing_key)) is None


def test_malformed_jwk_is_refused(clock, idp, signing_key):
    idp.jwks = {"keys": [{"kid": KID, "kty": "RSA", "n": "!!", "e": "AQAB"}]}
    assert oidc.validate_oidc_token(make_token(signing_key)) is None


# ---------------------------------------------------------------------------
# Discovery document checks
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "discovery",
    [
        pytest.param({"jwks_uri": JWKS_URI}, id="missing-issuer"),
        pytest.param({"issuer": "   ", "jwks_uri": JWKS_URI}, id="blank-issuer"),
        pytest.param(
            {
                "issuer": "https://idp.example.test/application/o/other",
                "jwks_uri": JWKS_URI,
            },
            id="issuer-mismatch",
        ),
        pytest.param({"issuer": DISCOVERED_ISSUER}, id="missing-jwks-uri"),
        pytest.param(
            {"issuer": DISCOVERED_ISSUER, "jwks_uri": "/jwks/"}, id="relative-jwks-uri"
        ),
        pytest.param(
            {
                "issuer": DISCOVERED_ISSUER,
                "jwks_uri": "https://attacker.example.test/jwks/",
            },
            id="cross-origin-jwks-uri",
        ),
        pytest.param(
            {
                "issuer": DISCOVERED_ISSUER,
                "jwks_uri": "https://idp.example.test:8443/jwks/",
            },
            id="other-port-jwks-uri",
        ),
        pytest.param(
            {"issuer": DISCOVERED_ISSUER, "jwks_uri": "http://idp.example.test/jwks/"},
            id="plaintext-jwks-uri",
        ),
    ],
)
def test_untrustworthy_discovery_disables_validation(
    clock, idp, signing_key, discovery
):
    idp.discovery = discovery

    assert oidc.validate_oidc_token(make_token(signing_key)) is None
    # No key material is fetched from a document that failed validation.
    assert idp.jwks_fetches == 0
    assert oidc.fetch_oidc_configuration() is None


def test_issuer_comparison_ignores_case_and_trailing_slash(clock, idp, signing_key):
    idp.discovery = {
        "issuer": "HTTPS://IDP.EXAMPLE.TEST/application/o/whisperdoc/",
        "jwks_uri": JWKS_URI,
    }
    token = make_token(
        signing_key, iss="HTTPS://IDP.EXAMPLE.TEST/application/o/whisperdoc/"
    )
    assert oidc.validate_oidc_token(token) is not None


def test_loopback_issuer_may_use_plain_http(monkeypatch, signing_key):
    issuer = "http://localhost:9000/application/o/whisperdoc"
    idp = FakeIdP(
        jwks={"keys": [public_jwk(signing_key, KID)]},
        discovery={"issuer": issuer, "jwks_uri": issuer + "/jwks/"},
    )
    install_idp(monkeypatch, idp, issuer=issuer)
    try:
        assert oidc.validate_oidc_token(make_token(signing_key, iss=issuer)) is not None
    finally:
        clear_oidc_caches()


def test_failed_discovery_is_retried_on_the_next_request(clock, idp, signing_key):
    idp.discovery_status = 503
    assert oidc.validate_oidc_token(make_token(signing_key)) is None

    idp.discovery_status = 200
    assert oidc.validate_oidc_token(make_token(signing_key)) is not None
    assert idp.discovery_fetches == 2


def test_jwks_outage_fails_closed_and_recovers(clock, idp, signing_key):
    idp.jwks_status = 500
    assert oidc.validate_oidc_token(make_token(signing_key)) is None

    idp.jwks_status = 200
    assert oidc.validate_oidc_token(make_token(signing_key)) is not None


def test_cached_jwks_without_reachable_discovery_fails_closed(clock, idp, signing_key):
    assert oidc.validate_oidc_token(make_token(signing_key)) is not None
    # Discovery cache expires while the IdP is down; JWKS is still cached.
    oidc._oidc_config_cache.clear()
    idp.discovery_status = 503

    assert oidc.validate_oidc_token(make_token(signing_key)) is None


def test_disabled_oidc_rejects_everything_without_network(
    monkeypatch, idp, signing_key
):
    install_idp(monkeypatch, idp, issuer="")
    try:
        assert oidc.validate_oidc_token(make_token(signing_key)) is None
        assert oidc.fetch_jwks() is None
        assert idp.fetched == []
    finally:
        clear_oidc_caches()


# ---------------------------------------------------------------------------
# Startup warmup
# ---------------------------------------------------------------------------


def test_warmup_primes_both_caches(clock, idp, signing_key):
    oidc.warmup_oidc()
    assert idp.discovery_fetches == 1 and idp.jwks_fetches == 1

    assert oidc.validate_oidc_token(make_token(signing_key)) is not None
    assert len(idp.fetched) == 2


def test_warmup_survives_an_unreachable_idp(clock, idp):
    idp.discovery_status = 502
    oidc.warmup_oidc()
    assert idp.jwks_fetches == 0

    idp.discovery_status = 200
    idp.jwks_status = 502
    oidc.warmup_oidc()
    assert idp.jwks_fetches == 1


def test_warmup_is_a_no_op_when_oidc_is_disabled(monkeypatch, idp):
    install_idp(monkeypatch, idp, issuer="")
    oidc.warmup_oidc()
    assert idp.fetched == []


# ---------------------------------------------------------------------------
# Issuer URL configuration check
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("url", "allowed"),
    [
        ("", True),
        (ISSUER, True),
        ("http://localhost:9000/o/app/", True),
        ("http://127.0.0.1/o/app/", True),
        ("http://[::1]:9000/o/app/", True),
        ("http://idp.example.test/o/app/", False),
        ("ftp://idp.example.test/o/app/", False),
        ("https://idp.example.test/o/a pp/", False),
        ("https://idp.example.test/o/app/\n", False),
        ("https://idp.example.test/o/\tapp/", False),
        ("idp.example.test/o/app", False),
        ("https:///o/app", False),
    ],
)
def test_issuer_url_must_be_absolute_and_https_unless_loopback(url, allowed):
    assert oidc._validate_oidc_url(url) is allowed
