-- Store both daily and cumulative allbrand snapshots for clear reporting.

ALTER TABLE public.allbrand_reports
ADD COLUMN IF NOT EXISTS brand_data_daily JSONB DEFAULT '{}'::jsonb,
ADD COLUMN IF NOT EXISTS leasing_sales_daily JSONB DEFAULT '{}'::jsonb,
ADD COLUMN IF NOT EXISTS daily_total_units INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS cumulative_total_units INTEGER DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_allbrand_reports_daily_total
ON public.allbrand_reports (daily_total_units);

CREATE INDEX IF NOT EXISTS idx_allbrand_reports_cumulative_total
ON public.allbrand_reports (cumulative_total_units);

-- Backfill for old rows: treat current cumulative as daily when daily is missing.
UPDATE public.allbrand_reports
SET
  brand_data_daily = CASE
    WHEN jsonb_typeof(brand_data_daily) = 'object' THEN brand_data_daily
    WHEN jsonb_typeof(brand_data) = 'object' THEN brand_data
    ELSE '{}'::jsonb
  END,
  leasing_sales_daily = CASE
    WHEN jsonb_typeof(leasing_sales_daily) = 'object' THEN leasing_sales_daily
    WHEN jsonb_typeof(leasing_sales) = 'object' THEN leasing_sales
    ELSE '{}'::jsonb
  END
WHERE brand_data_daily IS NULL
   OR leasing_sales_daily IS NULL;

-- Recalculate totals from JSON structure.
WITH calc AS (
  SELECT
    r.id,
    COALESCE((
      SELECT SUM(
        COALESCE((b.value->>'under_2m')::int, 0) +
        COALESCE((b.value->>'2m_4m')::int, 0) +
        COALESCE((b.value->>'4m_6m')::int, 0) +
        COALESCE((b.value->>'above_6m')::int, 0)
      )
      FROM jsonb_each(
        CASE
          WHEN jsonb_typeof(r.brand_data_daily) = 'object' THEN r.brand_data_daily
          ELSE '{}'::jsonb
        END
      ) b
    ), 0) AS daily_total,
    COALESCE((
      SELECT SUM(
        COALESCE((b.value->>'under_2m')::int, 0) +
        COALESCE((b.value->>'2m_4m')::int, 0) +
        COALESCE((b.value->>'4m_6m')::int, 0) +
        COALESCE((b.value->>'above_6m')::int, 0)
      )
      FROM jsonb_each(
        CASE
          WHEN jsonb_typeof(r.brand_data) = 'object' THEN r.brand_data
          ELSE '{}'::jsonb
        END
      ) b
    ), 0) AS cumulative_total
  FROM public.allbrand_reports r
)
UPDATE public.allbrand_reports r
SET
  daily_total_units = c.daily_total,
  cumulative_total_units = c.cumulative_total
FROM calc c
WHERE r.id = c.id;
