# DB MIGRATION PHASE 5 SQL NOTES
**Date:** 10 March 2026  
**SQL Draft:** [supabase/PHASE5_CUTOVER_LEADERBOARD_AND_SATOR_BONUS.sql](../supabase/PHASE5_CUTOVER_LEADERBOARD_AND_SATOR_BONUS.sql)

Tujuan draft ini:
- memindahkan leaderboard, live feed, dan consumer bonus SATOR ke `sales_bonus_events`

Cakupan:
- `get_live_feed(...)`
- `get_leaderboard_feed(...)`
- `get_team_leaderboard(...)`
- `get_team_live_feed(...)`
- `get_sator_tim_detail(...)`

Prinsip:
- contract output JSON/field tetap dipertahankan
- nama field seperti `total_bonus` atau `estimated_bonus` tetap dipakai bila dibutuhkan frontend
- sumber bonus di balik layar dipindah ke ledger event
