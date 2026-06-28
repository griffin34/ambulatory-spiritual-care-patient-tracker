// Copyright (C) 2026 Jason Griffin
// SPDX-License-Identifier: GPL-3.0-only

// Single source of truth for the in-app "What's New" notes. Keep the latest
// entry in sync with the matching version section in CHANGELOG.md.
export const RELEASE_NOTES = {
  version: '1.1.0',
  date: '2026-06-30',
  highlights: [
    'Record SDAT distress scores (beginning & ending) with dates and a notes field — each editable on its own, without opening the full profile edit.',
    'SDAT % improvement is calculated automatically and shown as you enter scores.',
    'New SDAT Improvement report — percent improvement aggregated across patients by date range.',
    'Reports now have a single report picker and date range — run one report, or all of them, at once.',
    'Delete entries made in error (soft delete) and restore them later; deleted records keep their history.',
    'Sort the Work Queue by any column heading.',
    'Admin list values (religions, languages, etc.) are now sorted A–Z.',
    'Print any of the main screens, including reports — tailored to print cleanly, not just a screenshot of the screen.',
  ],
}
