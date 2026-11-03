\set ON_ERROR_STOP on
-- Check the restored rows themselves, not only constraint metadata.
DO $$
DECLARE fk record; joins text; nonnull text; valid boolean;
BEGIN
  IF (SELECT count(*) FROM public.schema_migration) <> 7 THEN
    RAISE EXCEPTION 'Expected migrations 001-007';
  END IF;
  IF EXISTS (SELECT FROM pg_constraint WHERE connamespace = 'public'::regnamespace
             AND NOT convalidated) THEN
    RAISE EXCEPTION 'Unvalidated constraint';
  END IF;
  IF EXISTS (SELECT FROM pg_index i JOIN pg_class c ON c.oid = i.indrelid
             WHERE c.relnamespace = 'public'::regnamespace
               AND (NOT i.indisvalid OR NOT i.indisready)) THEN
    RAISE EXCEPTION 'Invalid index';
  END IF;
  FOR fk IN SELECT * FROM pg_constraint
            WHERE connamespace = 'public'::regnamespace AND contype = 'f'
  LOOP
    SELECT string_agg(format('c.%I = p.%I', a.attname, b.attname), ' AND '),
           string_agg(format('c.%I IS NOT NULL', a.attname), ' AND ')
      INTO joins, nonnull
    FROM unnest(fk.conkey, fk.confkey) AS keys(child, parent)
    JOIN pg_attribute a ON a.attrelid = fk.conrelid AND a.attnum = keys.child
    JOIN pg_attribute b ON b.attrelid = fk.confrelid AND b.attnum = keys.parent;
    EXECUTE format('SELECT NOT EXISTS (SELECT FROM %s c WHERE %s
                    AND NOT EXISTS (SELECT FROM %s p WHERE %s))',
                   fk.conrelid::regclass, nonnull, fk.confrelid::regclass, joins) INTO valid;
    IF NOT valid THEN RAISE EXCEPTION 'Broken FK: %', fk.conname; END IF;
  END LOOP;
END $$;
SELECT 'integrity: migrations, constraints, indexes, FK rows OK';
