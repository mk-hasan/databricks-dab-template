from datetime import date

from src.example_source.utils.orders import clean_orders, daily_totals, sample_raw_orders


def test_sample_includes_invalid_rows():
    rows = sample_raw_orders(n=5, as_of=date(2026, 8, 17))
    assert any(not r["order_id"] or r["qty"] <= 0 for r in rows)


def test_clean_orders_drops_invalid_and_adds_revenue():
    rows = sample_raw_orders(n=5, as_of=date(2026, 8, 17))
    cleaned = clean_orders(rows)
    assert all(r["order_id"] and r["qty"] > 0 and r["unit_price"] > 0 for r in cleaned)
    assert len(cleaned) == 5
    assert cleaned[0]["revenue"] == cleaned[0]["qty"] * cleaned[0]["unit_price"]


def test_daily_totals_aggregates_by_date():
    cleaned = clean_orders(sample_raw_orders(n=8, as_of=date(2026, 8, 17)))
    totals = daily_totals(cleaned)
    assert totals
    assert set(totals[0]) == {"order_date", "order_count", "qty_sum", "revenue"}
    assert sum(t["order_count"] for t in totals) == len(cleaned)
