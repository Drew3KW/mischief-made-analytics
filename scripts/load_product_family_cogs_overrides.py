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
TABLE_ID = "product_family_cogs_overrides_latest"

VALID_OVERRIDE_ACTIONS = {
    "estimate_cogs",
    "exclude_from_profit_model",
}


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

    match = re.search(r"-?\d+(?:\.\d+)?", cleaned.replace(",", ""))

    if match is None:
        return None

    return match.group(0)


def build_output_row(
    *,
    source_file_name: str,
    source_row_number: int,
    loaded_at: str,
    row: dict[str, str],
) -> dict[str, Any]:
    product_family_key = clean_string(row.get("product_family_key"))
    product_family_name = clean_string(row.get("product_family_name"))
    unit_cogs_raw = clean_string(row.get("unit_cogs"))
    override_action = normalize_key(row.get("override_action"))
    override_reason = clean_string(row.get("override_reason"))
    notes = clean_string(row.get("notes"))

    if override_action is not None and override_action not in VALID_OVERRIDE_ACTIONS:
        raise ValueError(
            "Invalid override_action on source row "
            f"{source_row_number}: {override_action}"
        )

    unit_cogs = parse_money(unit_cogs_raw)

    return {
        "source_file_name": source_file_name,
        "source_row_number": source_row_number,
        "loaded_at": loaded_at,
        "product_family_key": product_family_key,
        "product_family_name": product_family_name,
        "unit_cogs_raw": unit_cogs_raw,
        "override_action": override_action,
        "override_reason": override_reason,
        "notes": notes,
        "normalized_product_family_key": normalize_key(product_family_key),
        "unit_cogs": unit_cogs,
        "is_estimate_cogs": override_action == "estimate_cogs",
        "is_exclude_from_profit_model": override_action == "exclude_from_profit_model",
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
        reader = csv.DictReader(csv_file)

        required_columns = {
            "product_family_key",
            "product_family_name",
            "unit_cogs",
            "override_action",
            "override_reason",
            "notes",
        }

        missing_columns = required_columns - set(reader.fieldnames or [])

        if missing_columns:
            raise ValueError(
                "Missing required CSV columns: "
                + ", ".join(sorted(missing_columns))
            )

        for source_row_number, row in enumerate(reader, start=2):
            if all(clean_string(value) is None for value in row.values()):
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
            bigquery.SchemaField("product_family_key", "STRING"),
            bigquery.SchemaField("product_family_name", "STRING"),
            bigquery.SchemaField("unit_cogs_raw", "STRING"),
            bigquery.SchemaField("override_action", "STRING"),
            bigquery.SchemaField("override_reason", "STRING"),
            bigquery.SchemaField("notes", "STRING"),
            bigquery.SchemaField("normalized_product_family_key", "STRING"),
            bigquery.SchemaField("unit_cogs", "NUMERIC"),
            bigquery.SchemaField("is_estimate_cogs", "BOOL"),
            bigquery.SchemaField("is_exclude_from_profit_model", "BOOL"),
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

    print(f"Loaded {destination_table.num_rows} rows into {table_ref}.")
    print(f"Source file: {csv_path}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Load private product-family COGS overrides into BigQuery."
    )
    parser.add_argument(
        "--csv-path",
        default="local_data/cogs/product_family_cogs_overrides_latest.csv",
        help="Path to the local private product-family COGS override CSV.",
    )

    args = parser.parse_args()
    load_csv_to_bigquery(Path(args.csv_path))


if __name__ == "__main__":
    main()