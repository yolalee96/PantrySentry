-- Run ONCE on the live database after deploying this backend update.
-- Discards assessed before the new quantity_conversions data was loaded
-- were stored as EXCLUDED ("Missing quantity conversion"). Deleting those
-- rows lets the Impact tab re-assess them with the new conversions the
-- next time it's opened. ASSESSED rows are not touched, so figures already
-- shown never change. Nothing else is deleted.
DELETE FROM waste_impact_assessments WHERE assessment_status = 'EXCLUDED';
