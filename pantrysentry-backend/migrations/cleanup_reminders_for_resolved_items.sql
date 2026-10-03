-- One-off cleanup (safe to run on the live DB, only touches reminders).
-- Before the resolve endpoint started cancelling reminders itself,
-- reminders for items that were already consumed, discarded or donated
-- were left PENDING/TRIGGERED. This cancels those leftovers.
UPDATE reminders r
JOIN inventory_items ii ON ii.inventory_item_id = r.inventory_item_id
SET r.status = 'CANCELLED', r.cancelled_at = NOW()
WHERE ii.status IN ('CONSUMED', 'DISCARDED', 'DONATED')
  AND r.status IN ('PENDING', 'TRIGGERED');
