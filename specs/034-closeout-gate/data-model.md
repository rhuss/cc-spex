# Data Model: Deterministic closeout gate

No new data entities. The script reads an existing file (REVIEW-CODE.md) and produces an exit code.

## Entities (reference only, not modified)

- **REVIEW-CODE.md**: Markdown file with a severity summary table. Read-only input to the gate script.
- **Severity Summary Table**: A markdown table with columns Severity, Found, Fixed, Remaining. The gate extracts the Remaining values for Critical and Important rows.
