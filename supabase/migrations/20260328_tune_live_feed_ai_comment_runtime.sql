update public.ai_feature_settings
set config_json = jsonb_set(
      jsonb_set(
        coalesce(config_json, '{}'::jsonb),
        '{delay_seconds}',
        '0'::jsonb,
        true
      ),
      '{min_output_chars}',
      '28'::jsonb,
      true
    ),
    updated_at = now()
where feature_key = 'live_feed_sales_comment';
