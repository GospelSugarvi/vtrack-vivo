-- Test get_users_with_hierarchy function

-- Get current period
SELECT 
    id,
    period_name,
    start_date,
    end_date
FROM target_periods
WHERE extract(month from start_date) = extract(month from current_date)
  AND extract(year from start_date) = extract(year from current_date)
LIMIT 1;

-- Test with promotor role
SELECT * FROM get_users_with_hierarchy(
    (SELECT id FROM target_periods 
     WHERE extract(month from start_date) = extract(month from current_date)
       AND extract(year from start_date) = extract(year from current_date)
     LIMIT 1),
    'promotor'
)
LIMIT 5;

-- Test with sator role
SELECT * FROM get_users_with_hierarchy(
    (SELECT id FROM target_periods 
     WHERE extract(month from start_date) = extract(month from current_date)
       AND extract(year from start_date) = extract(year from current_date)
     LIMIT 1),
    'sator'
)
LIMIT 5;

-- Test with spv role
SELECT * FROM get_users_with_hierarchy(
    (SELECT id FROM target_periods 
     WHERE extract(month from start_date) = extract(month from current_date)
       AND extract(year from start_date) = extract(year from current_date)
     LIMIT 1),
    'spv'
)
LIMIT 5;
