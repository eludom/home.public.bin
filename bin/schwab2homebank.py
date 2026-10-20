#!/usr/bin/env python3
"""
bank2homebank.py — Convert bank CSV export to HomeBank CSV import format.

HomeBank import format (semicolon-separated, 8 columns):
  date;paymode;info;payee;memo;amount;category;tags

  date     : MM-DD-YYYY  (configurable in HB prefs; default seems MM-DD-YYYY)
  paymode  : 0=None 1=Credit Card 2=Check 3=Cash 4=Transfer
             6=Debit Card 7=Standing Order 8=Electronic Payment
             9=Deposit 10=FI Fee 11=Direct Debit
  info     : check number or other reference string
  payee    : payee name (left blank here; use HB Assignments to auto-fill)
  memo     : transaction description
  amount   : signed decimal  (negative = withdrawal, positive = deposit)
  category : left blank (use HB Assignments)
  tags     : left blank (mandatory column since HB 4.5, but can be empty)

Input CSV columns expected:
  Date, Status, Type, CheckNumber, Description, Withdrawal, Deposit, RunningBalance

Usage:
  python3 bank2homebank.py input.csv [output.csv]
  (output defaults to input filename with _homebank suffix)
"""

import csv
import sys
import os
import re
from datetime import datetime

# ---------------------------------------------------------------------------
# Paymode mapping: bank "Type" field -> HomeBank paymode integer
# Extend as needed for your institution's export codes.
# ---------------------------------------------------------------------------
PAYMODE_MAP = {
    "VISA":       1,   # Credit Card  (change to 6 if it's a debit Visa)
    "MC":         1,   # Mastercard
    "CHECK":      2,   # Check
    "CASH":       3,   # Cash
    "ACH":        8,   # Electronic Payment
    "TRANSFER":   4,   # Transfer
    "INTADJUST":  10,  # Interest adjustment -> FI Fee / interest
    "DEPOSIT":    9,   # Deposit
    "DIRECTDEBIT":11,  # Direct Debit
}
PAYMODE_DEFAULT = 0   # None — used when Type not in the map


def parse_amount(value: str) -> str | None:
    """Strip currency symbols/commas, return signed decimal string or None."""
    if not value or not value.strip():
        return None
    cleaned = re.sub(r"[$,\s]", "", value.strip())
    try:
        return str(float(cleaned))
    except ValueError:
        return None


def convert_date(date_str: str) -> str:
    """Convert MM/DD/YYYY -> MM-DD-YYYY (HomeBank default import format)."""
    for fmt in ("%m/%d/%Y", "%m-%d-%Y", "%Y-%m-%d", "%d/%m/%Y"):
        try:
            dt = datetime.strptime(date_str.strip(), fmt)
            return dt.strftime("%m-%d-%Y")
        except ValueError:
            continue
    raise ValueError(f"Unrecognised date format: {date_str!r}")


def convert(input_path: str, output_path: str) -> int:
    """Convert bank CSV to HomeBank CSV.  Returns number of rows written."""
    rows_written = 0

    with open(input_path, newline="", encoding="utf-8-sig") as fin, \
         open(output_path, "w", newline="", encoding="utf-8") as fout:

        reader = csv.DictReader(fin)
        writer = csv.writer(fout, delimiter=";", quoting=csv.QUOTE_MINIMAL)

        # Optional header — HomeBank ignores it but it helps humans
        writer.writerow(["date", "paymode", "info", "payee",
                         "memo", "amount", "category", "tags"])

        for lineno, row in enumerate(reader, start=2):   # 1 = header
            # ---- date ----
            try:
                date = convert_date(row.get("Date", ""))
            except ValueError as exc:
                print(f"WARNING line {lineno}: {exc} — skipping row", file=sys.stderr)
                continue

            # ---- paymode ----
            tx_type = row.get("Type", "").strip().upper()
            paymode = PAYMODE_MAP.get(tx_type, PAYMODE_DEFAULT)

            # ---- info (check number) ----
            info = row.get("CheckNumber", "").strip()

            # ---- payee (left blank; configure via HB Assignments) ----
            payee = ""

            # ---- memo ----
            memo = row.get("Description", "").strip()

            # ---- amount (withdrawal = negative, deposit = positive) ----
            withdrawal = parse_amount(row.get("Withdrawal", ""))
            deposit    = parse_amount(row.get("Deposit", ""))

            if withdrawal is not None:
                amount = f"-{withdrawal}"
            elif deposit is not None:
                amount = deposit
            else:
                print(f"WARNING line {lineno}: no amount found — skipping row",
                      file=sys.stderr)
                continue

            # ---- category & tags (blank; fill in HB or extend this script) ----
            category = ""
            tags = ""

            writer.writerow([date, paymode, info, payee,
                             memo, amount, category, tags])
            rows_written += 1

    return rows_written


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    input_path = sys.argv[1]

    if len(sys.argv) >= 3:
        output_path = sys.argv[2]
    else:
        base, _ = os.path.splitext(input_path)
        output_path = f"{base}_homebank.csv"

    if not os.path.isfile(input_path):
        print(f"ERROR: input file not found: {input_path}", file=sys.stderr)
        sys.exit(1)

    n = convert(input_path, output_path)
    print(f"Wrote {n} transaction(s) to {output_path}")


if __name__ == "__main__":
    main()
    
