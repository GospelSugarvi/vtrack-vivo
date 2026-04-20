create unique index if not exists product_variants_active_identity_uniq
on public.product_variants (
  product_id,
  upper(trim(coalesce(ram_rom, ''))),
  upper(trim(coalesce(color, '')))
)
where deleted_at is null;
