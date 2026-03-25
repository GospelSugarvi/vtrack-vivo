-- Compatibility fix for legacy queries that still read products.name
-- Source of truth remains model_name.

ALTER TABLE public.products
ADD COLUMN IF NOT EXISTS name TEXT;

-- Backfill legacy name from model_name for existing rows.
UPDATE public.products
SET name = model_name
WHERE COALESCE(name, '') = ''
  AND COALESCE(model_name, '') <> '';

CREATE OR REPLACE FUNCTION public.sync_products_name_model_name()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  -- If model_name is empty but name is provided, keep data usable.
  IF COALESCE(NEW.model_name, '') = '' AND COALESCE(NEW.name, '') <> '' THEN
    NEW.model_name := NEW.name;
  END IF;

  -- Maintain legacy name for old clients.
  IF COALESCE(NEW.name, '') = '' AND COALESCE(NEW.model_name, '') <> '' THEN
    NEW.name := NEW.model_name;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_products_sync_name_model_name ON public.products;
CREATE TRIGGER trg_products_sync_name_model_name
BEFORE INSERT OR UPDATE ON public.products
FOR EACH ROW
EXECUTE FUNCTION public.sync_products_name_model_name();
