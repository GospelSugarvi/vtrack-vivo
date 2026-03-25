-- Fix RLS Policy for stock_movement_log
-- Missing policies caused 42501 error on insert

-- Allow Promotor to insert logs for their own movements
CREATE POLICY "Promotor insert movement" ON stock_movement_log FOR INSERT WITH CHECK (
  moved_by = auth.uid()
);

-- Allow Promotor to view logs related to their own actions or store
CREATE POLICY "Promotor view movement" ON stock_movement_log FOR SELECT USING (
  moved_by = auth.uid()
);

-- Allow Admin/Manager/SPV/SATOR to view all logs
CREATE POLICY "Management view movement" ON stock_movement_log FOR SELECT USING (
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role IN ('admin', 'manager', 'spv', 'sator'))
);

-- Also add missing policy for stock_transfer_items
CREATE POLICY "Transfer items policy" ON stock_transfer_items FOR ALL USING (
  EXISTS (
    SELECT 1 FROM stock_transfer_requests str
    WHERE str.id = stock_transfer_items.transfer_request_id
    AND (
      str.requested_by = auth.uid() OR 
      str.approved_by = auth.uid() OR
      EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role IN ('admin', 'manager', 'spv', 'sator'))
    )
  )
);
