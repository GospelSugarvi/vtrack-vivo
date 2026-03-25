# RPC Contract Final

Dokumen ini adalah daftar RPC final yang diizinkan untuk arsitektur baru.  
Tujuannya: tidak ada lagi RPC dobel untuk arti yang sama.

## Aturan umum

- RPC `home` hanya membaca summary table.
- RPC `ranking` hanya membaca leaderboard summary.
- RPC `detail` boleh membaca fact table.
- Nama RPC pakai bahasa Inggris snake_case.
- Satu RPC = satu tujuan jelas.

## Home RPC

### `get_promotor_home_summary`

Input:

- `p_user_id uuid`
- `p_period_tab text` with values `daily`, `weekly`, `monthly`
- `p_reference_date date`

Output minimum:

- header data
- target summary
- bonus summary
- activity summary
- ranking snippet

Source utama:

- `summary_user_daily`
- `summary_user_period`
- `summary_leaderboard_daily` or `summary_leaderboard_period`

### `get_sator_home_summary`

Input:

- `p_user_id uuid`
- `p_period_tab text`
- `p_reference_date date`

Output minimum:

- target team summary
- team snapshot
- alert summary
- quick access counters

Source utama:

- `summary_team_daily`
- `summary_team_period`
- `summary_leaderboard_daily`
- `summary_leaderboard_period`

### `get_spv_home_summary`

Input:

- `p_user_id uuid`
- `p_period_tab text`
- `p_reference_date date`

Output minimum:

- target area summary
- structure snapshot
- progress monitoring
- approval snapshot

Source utama:

- `summary_team_daily`
- `summary_team_period`

### `get_trainer_home_summary`

Input:

- `p_user_id uuid`
- `p_period_tab text`
- `p_reference_date date`

Output minimum:

- focus product summary
- product learning summary
- promotor ranking snippet

Source utama:

- `summary_user_daily`
- `summary_user_period`
- `summary_leaderboard_daily`
- `summary_leaderboard_period`

### `get_manager_home_summary`

Input:

- `p_user_id uuid`
- `p_period_tab text`
- `p_reference_date date`

Output minimum:

- business snapshot
- spv control snapshot
- area alert summary

Source utama:

- `summary_team_daily`
- `summary_team_period`
- `summary_leaderboard_daily`
- `summary_leaderboard_period`

### `get_admin_home_summary`

Input:

- `p_reference_date date`

Output minimum:

- system snapshot
- user snapshot
- target snapshot
- hierarchy snapshot

## Workplace RPC

### `get_promotor_workplace_summary`

Output minimum:

- sell out shortcuts
- bonus shortcuts
- activity shortcuts
- store operation shortcuts

### `get_sator_workplace_summary`

Output minimum:

- visiting counters
- sell out monitoring counters
- sell in monitoring counters
- team status counters

### `get_spv_workplace_summary`

Output minimum:

- sator monitoring counters
- promotor monitoring counters
- approval counters
- operational bottlenecks

### `get_trainer_workplace_summary`

Output minimum:

- active focus products
- learning catalog counts
- brand comparison counts

### `get_manager_workplace_summary`

Output minimum:

- spv control counts
- structure counts
- business monitoring counters

### `get_admin_workplace_summary`

Output minimum:

- user counts
- hierarchy counts
- assignment counts
- target setup counts

## Ranking RPC

### `get_promotor_ranking`

Input:

- `p_scope_code text`
- `p_period_kind text` with values `daily`, `weekly`, `monthly`
- `p_reference_date date`
- `p_limit integer`

Output minimum:

- rank position
- user name
- store name
- sell out all type pct
- focus product pct
- final score

### `get_sator_ranking`

Output minimum:

- `sator_ranking`
- `promotor_ranking`

### `get_spv_ranking`

Output minimum:

- `sator_ranking`
- `promotor_ranking`

### `get_trainer_ranking`

Output minimum:

- `promotor_ranking`

### `get_manager_ranking`

Output minimum:

- `spv_ranking`
- `sator_ranking`
- `promotor_ranking`

## Detail RPC

### `get_target_detail`

Input:

- `p_user_id uuid`
- `p_role_code text`
- `p_period_tab text`
- `p_reference_date date`

Output minimum:

- target monthly
- active week
- week date range
- week weight
- working days
- daily target math
- actual
- remaining
- achievement

### `get_sell_out_detail`

Output:

- list raw sell out transactions
- filter by role scope

### `get_sell_in_detail`

Output:

- list raw sell in transactions
- filter by role scope

### `get_visit_detail`

Output:

- list raw visit transactions

### `get_product_training_detail`

Output:

- focus products
- special types
- product advantages
- brand comparisons

## Automation RPC

### `build_best_performance_post_jobs`

Purpose:

- create scheduled records in `motivational_posts`

### `generate_best_performance_post`

Purpose:

- render image for one scheduled post

### `dispatch_best_performance_post`

Purpose:

- send image to global SPV group chat

## Guardrails

- Jangan menambah RPC baru kalau kontrak di dokumen ini sudah mencakup arti yang sama.
- Jangan pakai nama lama yang kabur seperti `get_target_dashboard` untuk sistem baru.
- Semua payload home harus ringkas dan siap dipakai langsung di UI.
