-- Comments from SPV/SATOR on store visiting evaluation.

CREATE TABLE IF NOT EXISTS public.store_visit_comments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  store_id UUID NOT NULL REFERENCES public.stores(id) ON DELETE CASCADE,
  visit_id UUID REFERENCES public.store_visits(id) ON DELETE SET NULL,
  author_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  target_sator_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  comment_text TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_store_visit_comments_store
ON public.store_visit_comments (store_id, created_at DESC);

ALTER TABLE public.store_visit_comments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "store_visit_comments_select" ON public.store_visit_comments;
CREATE POLICY "store_visit_comments_select"
ON public.store_visit_comments
FOR SELECT
USING (
  EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = auth.uid()
      AND u.role IN ('admin', 'manager')
  )
  OR author_id = auth.uid()
  OR target_sator_id = auth.uid()
  OR EXISTS (
    SELECT 1
    FROM public.users spv
    JOIN public.users sator ON sator.id = store_visit_comments.target_sator_id
    WHERE spv.id = auth.uid()
      AND spv.role = 'spv'
      AND spv.area = sator.area
  )
);

DROP POLICY IF EXISTS "store_visit_comments_insert" ON public.store_visit_comments;
CREATE POLICY "store_visit_comments_insert"
ON public.store_visit_comments
FOR INSERT
WITH CHECK (
  author_id = auth.uid()
  AND EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = auth.uid()
      AND u.role IN ('spv', 'sator', 'admin', 'manager')
  )
);

CREATE OR REPLACE FUNCTION public.update_store_visit_comments_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_update_store_visit_comments_updated_at
ON public.store_visit_comments;

CREATE TRIGGER trigger_update_store_visit_comments_updated_at
BEFORE UPDATE ON public.store_visit_comments
FOR EACH ROW
EXECUTE FUNCTION public.update_store_visit_comments_updated_at();
