CREATE TABLE IF NOT EXISTS members (
 uid text PRIMARY KEY, username text UNIQUE NOT NULL,
 password_hash text NOT NULL, space_id text NOT NULL DEFAULT 'mmemo'
);
CREATE TABLE IF NOT EXISTS sessions (
 access_hash text PRIMARY KEY, refresh_hash text UNIQUE NOT NULL,
 uid text NOT NULL REFERENCES members(uid), expires_at timestamptz NOT NULL,
 refresh_expires_at timestamptz NOT NULL
);
CREATE TABLE IF NOT EXISTS todos (
 id text PRIMARY KEY CHECK(length(id) BETWEEN 1 AND 100),
 space_id text NOT NULL, title text NOT NULL CHECK(length(title) BETWEEN 1 AND 200),
 due text NOT NULL DEFAULT '', done boolean NOT NULL DEFAULT false,
 created_by text NOT NULL REFERENCES members(uid), participants text[] NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 CHECK(cardinality(participants) BETWEEN 1 AND 2)
);
CREATE INDEX IF NOT EXISTS todos_space ON todos(space_id,created_at,id);
CREATE TABLE IF NOT EXISTS hearts (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 sender text NOT NULL REFERENCES members(uid), recipient text NOT NULL REFERENCES members(uid),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS hearts_recipient ON hearts(recipient,created_at,id);
CREATE TABLE IF NOT EXISTS mutations (
 uid text NOT NULL REFERENCES members(uid), request_id uuid NOT NULL,
 fingerprint text NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(uid,request_id)
);
CREATE OR REPLACE FUNCTION notify_mmemo() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_TABLE_NAME='todos' THEN
  PERFORM pg_notify('mmemo_changes', json_build_object('kind','todos','space',COALESCE(NEW.space_id,OLD.space_id))::text);
 ELSE
  IF TG_OP='INSERT' THEN
   PERFORM pg_notify('mmemo_changes',json_build_object('kind','hearts','recipient',NEW.recipient)::text);
  END IF;
 END IF;
 RETURN NULL;
END $$;
DROP TRIGGER IF EXISTS todos_notify ON todos;
CREATE TRIGGER todos_notify AFTER INSERT OR UPDATE OR DELETE ON todos FOR EACH ROW EXECUTE FUNCTION notify_mmemo();
DROP TRIGGER IF EXISTS hearts_notify ON hearts;
CREATE TRIGGER hearts_notify AFTER INSERT ON hearts FOR EACH ROW EXECUTE FUNCTION notify_mmemo();
