from aps_kit.metadata import metadata_filename


def test_normalizes_features_subdir() -> None:
    assert (
        metadata_filename("features/Hunt The Wumpus.feature")
        == "features-hunt-the-wumpus-feature.json"
    )


def test_normalizes_nested() -> None:
    assert (
        metadata_filename("features/orders/Cancel Order.feature")
        == "features-orders-cancel-order-feature.json"
    )


def test_normalizes_mixed_case_and_punct() -> None:
    assert (
        metadata_filename("Features/API v2/Happy Path.feature")
        == "features-api-v2-happy-path-feature.json"
    )
