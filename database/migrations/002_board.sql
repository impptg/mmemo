-- A board belongs to the same authenticated space as the pair's todos.
CREATE TABLE board_heads (
 space_id text PRIMARY KEY, revision bigint NOT NULL DEFAULT 0,
 latest_by_user jsonb NOT NULL DEFAULT '{}'
);
CREATE TABLE board_elements (
 space_id text NOT NULL REFERENCES board_heads(space_id), id text NOT NULL,
 element jsonb NOT NULL, revision bigint NOT NULL, field_authors jsonb NOT NULL DEFAULT '{}',
 PRIMARY KEY(space_id,id)
);
CREATE TABLE board_files (
 space_id text NOT NULL REFERENCES board_heads(space_id), id text NOT NULL,
 data jsonb NOT NULL,
 PRIMARY KEY(space_id,id)
);
CREATE TABLE board_requests (
 uid text NOT NULL REFERENCES members(uid), request_id uuid NOT NULL,
 space_id text NOT NULL, fingerprint text NOT NULL, response jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(uid,request_id)
);
CREATE TABLE board_reads (
 space_id text NOT NULL REFERENCES board_heads(space_id), uid text NOT NULL REFERENCES members(uid),
 revision bigint NOT NULL DEFAULT 0, PRIMARY KEY(space_id,uid)
);
-- PostgreSQL invalidation keeps peers on other backend instances current too.
CREATE FUNCTION notify_board() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 PERFORM pg_notify('mmemo_board',json_build_object('space',NEW.space_id,'revision',NEW.revision)::text);
 RETURN NULL;
END $$;
CREATE TRIGGER board_notify AFTER UPDATE ON board_heads FOR EACH ROW EXECUTE FUNCTION notify_board();
