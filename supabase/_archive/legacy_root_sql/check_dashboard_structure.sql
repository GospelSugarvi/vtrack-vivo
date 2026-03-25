-- Cek struktur tabel dashboard_performance_metrics
SELECT 
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_name = 'dashboard_performance_metrics'
ORDER BY ordinal_position;
