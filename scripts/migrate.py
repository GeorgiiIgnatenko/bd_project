"""Atomic, checksum-verified forward migrations. Run: python3 -m scripts.migrate."""
import argparse
import hashlib

from scripts.db import ROOT, run_sql


def migration_sql(target=None):
    files = sorted((ROOT / "migrations").glob("[0-9]*.up.sql"))
    if target is not None and target not in [int(p.name[:3]) for p in files]:
        raise ValueError("Unknown target migration")
    known_versions = ",".join(str(int(p.name[:3])) for p in files)
    lines = ["BEGIN;", "SELECT pg_advisory_xact_lock(726041);", """
DO $$ BEGIN
  IF to_regclass('public.schema_migration') IS NULL
     AND to_regclass('public.role') IS NOT NULL THEN
    RAISE EXCEPTION 'Untracked legacy schema: reset the disposable lab database as documented';
  END IF;
END $$;
CREATE TABLE IF NOT EXISTS public.schema_migration (
  version integer PRIMARY KEY,
  filename text UNIQUE NOT NULL,
  checksum text NOT NULL,
  applied_at timestamptz NOT NULL DEFAULT now()
);
REVOKE ALL ON public.schema_migration FROM PUBLIC, news_app, news_analyst;
SET LOCAL search_path TO public, pg_catalog;
"""]
    lines.append(f"""
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM public.schema_migration WHERE version NOT IN ({known_versions})) THEN
    RAISE EXCEPTION 'Database contains a migration unknown to this checkout';
  END IF;
END $$;
""")
    for path in files:
        version = int(path.name[:3])
        checksum = hashlib.sha256(path.read_bytes()).hexdigest()
        lines += [f"""
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM public.schema_migration WHERE version = {version}
             AND (checksum <> '{checksum}' OR filename <> '{path.name}')) THEN
    RAISE EXCEPTION 'Migration {version} was modified after application';
  END IF;
END $$;
"""]
        if target is not None and version > target:
            continue
        lines += [f"SELECT EXISTS (SELECT 1 FROM public.schema_migration WHERE version = {version}) AS applied \\gset",
                  "\\if :applied", f"\\echo 'Already applied: {path.name}'", "\\else",
                  f"\\ir /workspace/migrations/{path.name}",
                  f"INSERT INTO public.schema_migration (version, filename, checksum) VALUES ({version}, '{path.name}', '{checksum}');",
                  "\\endif"]
    lines += ["\\ir /workspace/security/grants.sql", "COMMIT;"]
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", type=int, help="Apply through this version")
    parser.add_argument("--database", help="Defaults to POSTGRES_DB in the container")
    args = parser.parse_args()
    print(run_sql(migration_sql(args.target), database=args.database))


if __name__ == "__main__":
    main()
