from __future__ import annotations

import argparse
import csv
import re
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from google.cloud import bigquery


PROJECT_ID = "mischief-made-analytics"
DATASET_ID = "raw_load"
TABLE_ID = "product_cogs_manual_latest"


def clean_string(value: str | None) -> str | None:
    if value is None:
        return None

    cleaned = value.strip()

    if cleaned == "":
        return None

    return cleaned


def normalize_key(value: str | None) -> str | None:
    cleaned = clean_string(value)

    if cleaned is None:
        return None

    return cleaned.lower().strip()


def parse_money(value: str | None) -> str | None:
    cleaned = clean_string(value)

    if cleaned is None:
        return None

    # Some source values include notes such as "$34 (18)".
    # Use the first numeric-looking value as the reference amount.
    match = re.search(r"-?\d+(?:\.\d+)?", cleaned.replace(",", ""))

    if match is None:
        return None

    return match.group(0)


def row_value(row: list[str], index: int) -> str | None:
    if index >= len(row):
        return None

    return clean_string(row[index])


def build_output_row(
    *,
    source_file_name: str,
    source_row_number: int,
    loaded_at: str,
    row: list[str],
) -> dict[str, Any]:
    raw_notes_1 = row_value(row, 0)
    sku = row_value(row, 1)
    family_name = row_value(row, 2)
    price_raw = row_value(row, 3)
    profit_raw = row_value(row, 4)
    faire_15_fee_amount_raw = row_value(row, 5)
    faire_profit_raw = row_value(row, 6)
    raw_notes_2 = row_value(row, 7)
    cost_raw = row_value(row, 8)
    raw_notes_3 = row_value(row, 9)

    normalized_sku = normalize_key(sku)
    normalized_family_name = normalize_key(family_name)

    unit_cogs = parse_money(cost_raw)

    return {
        "source_file_name": source_file_name,
        "source_row_number": source_row_number,
        "loaded_at": loaded_at,
        "raw_notes_1": raw_notes_1,
        "sku": sku,
        "family_name": family_name,
        "price_raw": price_raw,
        "profit_raw": profit_raw,
        "faire_15_fee_amount_raw": faire_15_fee_amount_raw,
        "faire_profit_raw": faire_profit_raw,
        "raw_notes_2": raw_notes_2,
        "cost_raw": cost_raw,
        "raw_notes_3": raw_notes_3,
        "normalized_sku": normalized_sku,
        "normalized_family_name": normalized_family_name,
        "reference_price": parse_money(price_raw),
        "reference_profit": parse_money(profit_raw),
        "reference_faire_15_fee_amount": parse_money(faire_15_fee_amount_raw),
        "reference_faire_profit": parse_money(faire_profit_raw),
        "unit_cogs": unit_cogs,
        "has_sku": normalized_sku is not None,
        "has_family_name": normalized_family_name is not None,
        "has_unit_cogs": unit_cogs is not None,
    }


def load_csv_to_bigquery(csv_path: Path) -> None:
    if not csv_path.exists():
        raise FileNotFoundError(f"Missing CSV file: {csv_path}")

    client = bigquery.Client(project=PROJECT_ID)
    table_ref = f"{PROJECT_ID}.{DATASET_ID}.{TABLE_ID}"

    loaded_at = datetime.now(UTC).isoformat()
    output_rows: list[dict[str, Any]] = []

    with csv_path.open("r", encoding="utf-8-sig", newline="") as csv_file:
        reader = csv.reader(csv_file)

        try:
            header = next(reader)
        except StopIteration as exc:
            raise ValueError(f"CSV file is empty: {csv_path}") from exc

        print("Source header columns:")
        for index, column_name in enumerate(header, start=1):
            print(f"{index}. {column_name}")

        for source_row_number, row in enumerate(reader, start=2):
            # Skip fully blank rows.
            if all(clean_string(value) is None for value in row):
                continue

            output_rows.append(
                build_output_row(
                    source_file_name=csv_path.name,
                    source_row_number=source_row_number,
                    loaded_at=loaded_at,
                    row=row,
                )
            )

    job_config = bigquery.LoadJobConfig(
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
        schema=[
            bigquery.SchemaField("source_file_name", "STRING"),
            bigquery.SchemaField("source_row_number", "INT64"),
            bigquery.SchemaField("loaded_at", "TIMESTAMP"),
            bigquery.SchemaField("raw_notes_1", "STRING"),
            bigquery.SchemaField("sku", "STRING"),
            bigquery.SchemaField("family_name", "STRING"),
            bigquery.SchemaField("price_raw", "STRING"),
            bigquery.SchemaField("profit_raw", "STRING"),
            bigquery.SchemaField("faire_15_fee_amount_raw", "STRING"),
            bigquery.SchemaField("faire_profit_raw", "STRING"),
            bigquery.SchemaField("raw_notes_2", "STRING"),
            bigquery.SchemaField("cost_raw", "STRING"),
            bigquery.SchemaField("raw_notes_3", "STRING"),
            bigquery.SchemaField("normalized_sku", "STRING"),
            bigquery.SchemaField("normalized_family_name", "STRING"),
            bigquery.SchemaField("reference_price", "NUMERIC"),
            bigquery.SchemaField("reference_profit", "NUMERIC"),
            bigquery.SchemaField("reference_faire_15_fee_amount", "NUMERIC"),
            bigquery.SchemaField("reference_faire_profit", "NUMERIC"),
            bigquery.SchemaField("unit_cogs", "NUMERIC"),
            bigquery.SchemaField("has_sku", "BOOL"),
            bigquery.SchemaField("has_family_name", "BOOL"),
            bigquery.SchemaField("has_unit_cogs", "BOOL"),
        ],
    )

    load_job = client.load_table_from_json(
        output_rows,
        table_ref,
        job_config=job_config,
    )
    load_job.result()

    destination_table = client.get_table(table_ref)

    print()
    print(f"Loaded {destination_table.num_rows} rows into {table_ref}.")
    print(f"Source file: {csv_path}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Load private manual product COGS CSV into BigQuery raw_load."
    )
    parser.add_argument(
        "--csv-path",
        default="local_data/cogs/product_cogs_manual_latest.csv",
        help="Path to the local private COGS CSV export.",
    )

    args = parser.parse_args()
    load_csv_to_bigquery(Path(args.csv_path))


if __name__ == "__main__":
    main()