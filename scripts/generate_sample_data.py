"""Generate synthetic source data for the claims platform.

    python scripts/generate_sample_data.py

* ``data/source_extracts/Policies.csv`` and ``Claims.csv`` - the on-prem SQL
  Server tables (load them into a dev SQL Server to exercise the incremental copy)
* ``data/partner_inbound/policyholders_<date>.csv`` - the partner file drop
  (upload to the ``inbound/partner/`` container to fire the event trigger)

Defects are injected on purpose: mixed date formats, ``$`` amounts, paid >
claimed, unknown statuses, duplicate claim versions and malformed partner rows.
"""

from __future__ import annotations

import csv
import random
from datetime import date, datetime, timedelta
from pathlib import Path

DATA = Path(__file__).resolve().parents[1] / "data"
PRODUCTS = {"Motor": (450, 1800), "Home": (300, 1400), "Travel": (40, 220), "Pet": (180, 700)}
REGIONS = ["North", "South", "East", "West", "Central"]
CLAIM_TYPES = {
    "Motor": ["Collision", "Theft", "Glass"],
    "Home": ["Water Damage", "Fire", "Burglary"],
    "Travel": ["Medical", "Cancellation", "Baggage"],
    "Pet": ["Illness", "Accident"],
}
STATUSES = ["open", "under_review", "approved", "paid", "denied", "closed"]


def write(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    print(f"  {len(rows):>6,} rows -> {path.relative_to(DATA.parent)}")


def main(seed: int = 11) -> None:
    rng = random.Random(seed)
    holders, policies, claims = [], [], []

    for h in range(1, 801):
        holders.append(
            {
                "policyholder_id": f"PH{h:06d}",
                "full_name": f"customer {h}" if rng.random() < 0.1 else f"Customer {h}",
                "birth_year": rng.randint(1950, 2004),
                "region": rng.choice(REGIONS),
                "risk_tier": rng.choice("AABBBCCD"),
                "updated_at": "2026-09-30T23:00:00",
            }
        )
    holders[5]["risk_tier"] = "Z"  # invalid tier -> filtered in data flow
    holders.append({**holders[9], "region": "East", "updated_at": "2026-10-01T08:00:00"})  # newer version

    for p in range(1, 1201):
        product = rng.choice(list(PRODUCTS))
        start = date(2025, 1, 1) + timedelta(days=rng.randint(0, 600))
        policies.append(
            {
                "policy_id": f"POL{p:07d}",
                "policyholder_id": rng.choice(holders[:800])["policyholder_id"],
                "product_line": product,
                "coverage_limit": rng.choice([10000, 25000, 50000, 100000]),
                "annual_premium": round(rng.uniform(*PRODUCTS[product]), 2),
                "start_date": start.isoformat(),
                "end_date": (start + timedelta(days=365)).isoformat(),
                "channel": rng.choice(["broker", "online", "Online ", "agent"]),
                "ModifiedAt": datetime(2026, 9, rng.randint(1, 30), rng.randint(0, 23)).isoformat(),
            }
        )

    for c in range(1, 2201):
        policy = rng.choice(policies)
        incident = date(2026, 1, 1) + timedelta(days=rng.randint(0, 270))
        claimed = round(rng.uniform(150, 18000), 2)
        status = rng.choice(STATUSES)
        paid = claimed * rng.uniform(0.6, 1.0) if status in ("paid", "closed") else 0
        claims.append(
            {
                "claim_id": f"CLM{c:07d}",
                "policy_id": policy["policy_id"],
                "claim_type": rng.choice(CLAIM_TYPES[policy["product_line"]]),
                "incident_date": incident.isoformat() if rng.random() > 0.05 else incident.strftime("%m/%d/%Y"),
                "reported_date": (incident + timedelta(days=rng.randint(0, 25))).isoformat(),
                "claim_status": status if rng.random() > 0.05 else status.upper(),
                "claimed_amount": f"${claimed:,.2f}" if rng.random() < 0.1 else f"{claimed:.2f}",
                "paid_amount": f"{paid:.2f}",
                "adjuster_id": f"ADJ{rng.randint(1, 40):03d}",
                "ModifiedAt": datetime(2026, 10, 1, rng.randint(0, 23), rng.randint(0, 59)).isoformat(),
            }
        )
    for claim in rng.sample(claims, 25):  # defects the data flow must quarantine
        rng.choice(
            [
                lambda r: r.update(claimed_amount="-50"),
                lambda r: r.update(incident_date="2026-02-30"),
                lambda r: r.update(claim_status="lost"),
                lambda r: r.update(paid_amount="999999"),
            ]
        )(claim)
    claims += [{**c, "claim_status": "paid", "ModifiedAt": "2026-10-01T23:59:00"} for c in rng.sample(claims, 30)]

    print("Generating claims sample data ...")
    write(DATA / "source_extracts" / "Policies.csv", policies)
    write(DATA / "source_extracts" / "Claims.csv", claims)
    write(DATA / "partner_inbound" / "policyholders_2026-10-01.csv", holders)


if __name__ == "__main__":
    main()
