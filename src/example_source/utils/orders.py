"""Pure-Python helpers for the sample orders demo (unit-testable, no Spark)."""

from collections import defaultdict
from datetime import date, timedelta

PRODUCTS = ("flour", "sugar", "butter", "yeast")
REGIONS = ("DE", "AT", "NL")


def sample_raw_orders(n: int = 20, as_of: date | None = None) -> list[dict]:
    """Deterministic sample rows, including a few invalid ones for silver to drop."""
    as_of = as_of or date(2026, 8, 17)
    rows: list[dict] = []
    for i in range(n):
        rows.append(
            {
                "order_id": f"ORD-{i:04d}",
                "product": PRODUCTS[i % len(PRODUCTS)],
                "qty": (i % 5) + 1,
                "unit_price": 10.0 + (i % 3),
                "region": REGIONS[i % len(REGIONS)],
                "order_date": (as_of - timedelta(days=i % 7)).isoformat(),
                "status": "NEW",
            }
        )
    rows.append(
        {
            "order_id": "",
            "product": "flour",
            "qty": -1,
            "unit_price": 10.0,
            "region": "DE",
            "order_date": as_of.isoformat(),
            "status": "NEW",
        }
    )
    return rows


def is_valid_order(row: dict) -> bool:
    order_id = str(row.get("order_id") or "").strip()
    qty = row.get("qty") or 0
    unit_price = row.get("unit_price") or 0
    return bool(order_id) and qty > 0 and unit_price > 0


def clean_orders(rows: list[dict]) -> list[dict]:
    cleaned = []
    for row in rows:
        if not is_valid_order(row):
            continue
        cleaned.append(
            {
                **row,
                "order_id": str(row["order_id"]).strip(),
                "revenue": float(row["qty"]) * float(row["unit_price"]),
            }
        )
    return cleaned


def daily_totals(rows: list[dict]) -> list[dict]:
    agg: dict[str, dict] = defaultdict(lambda: {"order_count": 0, "qty_sum": 0, "revenue": 0.0})
    for row in rows:
        bucket = agg[row["order_date"]]
        bucket["order_count"] += 1
        bucket["qty_sum"] += int(row["qty"])
        bucket["revenue"] += float(row["revenue"])
    return [{"order_date": day, **metrics} for day, metrics in sorted(agg.items())]
