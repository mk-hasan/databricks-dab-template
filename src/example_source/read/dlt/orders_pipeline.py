# Databricks notebook source
# MAGIC %md
# MAGIC # Read — DLT orders pipeline (sample orders)
# MAGIC
# MAGIC Alternative read/ELT pattern under `read/dlt/` (declarative bronze → silver).
# MAGIC Same purpose as `read/bronze|silver|gold` notebooks, different implementation.
# MAGIC Deployed via `resources/example_source_read_dlt.pipeline.yml`.

# COMMAND ----------

import dlt
from pyspark.sql.functions import col

# COMMAND ----------

BRONZE_SCHEMA = (
    "order_id string, product string, qty int, unit_price double, "
    "region string, order_date string, status string"
)


def _sample_orders():
    rows = [
        ("ORD-0001", "flour", 2, 10.0, "DE", "2026-08-17", "NEW"),
        ("ORD-0002", "sugar", 3, 11.0, "AT", "2026-08-16", "NEW"),
        ("ORD-0003", "butter", 1, 12.0, "NL", "2026-08-15", "NEW"),
        ("", "flour", -1, 10.0, "DE", "2026-08-17", "NEW"),
        ("ORD-BAD", "sugar", 2, 0.0, "AT", "2026-08-17", "NEW"),
    ]
    return spark.createDataFrame(rows, schema=BRONZE_SCHEMA)


# COMMAND ----------

@dlt.table(
    name="dlt_orders_bronze",
    comment="DLT demo — raw-shaped orders (includes bad rows for expectations)",
    table_properties={"quality": "bronze"},
)
def dlt_orders_bronze():
    return _sample_orders()


# COMMAND ----------

@dlt.table(
    name="dlt_orders_silver",
    comment="DLT demo — cleaned orders with revenue",
    table_properties={"quality": "silver"},
)
@dlt.expect_or_drop("valid_order_id", "order_id IS NOT NULL AND order_id != ''")
@dlt.expect_or_drop("positive_qty", "qty > 0")
@dlt.expect_or_drop("positive_price", "unit_price > 0")
def dlt_orders_silver():
    return (
        dlt.read("dlt_orders_bronze")
        .withColumn("revenue", col("qty") * col("unit_price"))
    )
