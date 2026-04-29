from __future__ import annotations

import json
from pathlib import Path
from typing import Any


SAMPLE_DIR = Path("local_data/shopify_api_spike")
OUTPUT_PATH = SAMPLE_DIR / "field_inventory.md"


def collect_paths(value: Any, prefix: str = "") -> set[str]:
    paths: set[str] = set()

    if isinstance(value, dict):
        if not value:
            paths.add(prefix or "<root>")
            return paths

        for key, nested_value in value.items():
            next_prefix = f"{prefix}.{key}" if prefix else key
            paths.add(next_prefix)
            paths.update(collect_paths(nested_value, next_prefix))

    elif isinstance(value, list):
        list_prefix = f"{prefix}[]" if prefix else "[]"
        paths.add(list_prefix)

        for item in value:
            paths.update(collect_paths(item, list_prefix))

    else:
        paths.add(prefix or "<root>")

    return paths


def summarize_file(path: Path) -> str:
    with path.open("r", encoding="utf-8") as file:
        payload = json.load(file)

    paths = sorted(collect_paths(payload))

    lines = [
        f"## {path.name}",
        "",
        f"Total field paths: {len(paths)}",
        "",
        "```text",
    ]

    lines.extend(paths)
    lines.extend(["```", ""])

    return "\n".join(lines)


def main() -> None:
    expected_files = [
        "shop_connection_test.json",
        "orders_sample.json",
        "products_sample.json",
        "customers_sample.json",
    ]

    missing_files = [
        filename for filename in expected_files if not (SAMPLE_DIR / filename).exists()
    ]

    if missing_files:
        raise FileNotFoundError(
            "Missing expected Shopify API sample files: "
            + ", ".join(missing_files)
        )

    sections = [
        "# Shopify API Spike Field Inventory",
        "",
        "Generated from local Shopify API sample JSON files.",
        "",
        "This file is local scratch output and should not be committed.",
        "",
    ]

    for filename in expected_files:
        sections.append(summarize_file(SAMPLE_DIR / filename))

    OUTPUT_PATH.write_text("\n".join(sections), encoding="utf-8")
    print(f"Wrote {OUTPUT_PATH}")


if __name__ == "__main__":
    main()