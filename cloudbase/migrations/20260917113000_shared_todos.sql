CREATE TABLE public.mmemo_members (
  uid text PRIMARY KEY,
  username text NOT NULL UNIQUE,
  avatar text NOT NULL CHECK (avatar IN ('frog','raccoon')),
  space_id text NOT NULL
);
ALTER TABLE public.mmemo_members ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.mmemo_members TO authenticated;
CREATE POLICY member_self ON public.mmemo_members FOR SELECT TO authenticated USING (uid = auth.uid());
INSERT INTO public.mmemo_members VALUES
 ('2100541450115510274','user_pptg','frog','mmemo-development'),
 ('2100541456125558785','user_mm','raccoon','mmemo-development');

CREATE TABLE public.mmemo_todos (
  id text PRIMARY KEY CHECK (length(id) BETWEEN 1 AND 100),
  space_id text NOT NULL,
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 1 AND 200),
  due text NOT NULL DEFAULT '' CHECK (due='' OR (due ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$' AND to_char(due::timestamp,'YYYY-MM-DD"T"HH24:MI')=due)),
  done boolean NOT NULL DEFAULT false,
  created_by text NOT NULL REFERENCES public.mmemo_members(uid),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX mmemo_todos_space ON public.mmemo_todos(space_id,created_at,id);
ALTER TABLE public.mmemo_todos ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.mmemo_todos TO authenticated;
CREATE POLICY shared_todos ON public.mmemo_todos FOR SELECT TO authenticated USING (
 space_id IN (SELECT space_id FROM public.mmemo_members WHERE uid=auth.uid())
);
-- Only this transaction boundary can write; ordinary users cannot forge creators or membership.
CREATE FUNCTION public.mmemo_apply(changes jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
 caller text := auth.uid();
 shared_space text;
 item jsonb;
 patch jsonb;
 seen text[] := '{}';
 target text;
 rows_changed integer;
BEGIN
 SELECT space_id INTO shared_space FROM public.mmemo_members WHERE uid=caller;
 IF shared_space IS NULL THEN RAISE EXCEPTION 'Not a shared-space member' USING ERRCODE='42501'; END IF;
 IF jsonb_typeof(changes) IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Expected changes array'; END IF;
 IF jsonb_array_length(changes)>20 THEN RAISE EXCEPTION 'At most 20 changes'; END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(changes) LOOP
   IF jsonb_typeof(item) IS DISTINCT FROM 'object' OR (item - ARRAY['action','id','patch']) <> '{}'::jsonb THEN RAISE EXCEPTION 'Invalid change'; END IF;
   target := item->>'id'; patch := item->'patch';
   IF target IS NULL OR length(target) NOT BETWEEN 1 AND 100 OR target=ANY(seen) THEN RAISE EXCEPTION 'Invalid or repeated task ID'; END IF;
   seen := array_append(seen,target);
   IF item->>'action' IN ('create','update') THEN
     IF jsonb_typeof(patch) IS DISTINCT FROM 'object' OR (patch - ARRAY['title','due','done']) <> '{}'::jsonb THEN RAISE EXCEPTION 'Invalid fields'; END IF;
     IF (patch ? 'title' AND jsonb_typeof(patch->'title') IS DISTINCT FROM 'string') OR
        (patch ? 'due' AND jsonb_typeof(patch->'due') IS DISTINCT FROM 'string') OR
        (patch ? 'done' AND jsonb_typeof(patch->'done') IS DISTINCT FROM 'boolean') THEN RAISE EXCEPTION 'Invalid field types'; END IF;
   END IF;
   CASE item->>'action'
     WHEN 'create' THEN
       IF NOT (patch ? 'title') OR NOT (patch ? 'due') THEN RAISE EXCEPTION 'Missing fields'; END IF;
       INSERT INTO public.mmemo_todos(id,space_id,title,due,done,created_by)
         VALUES(target,shared_space,btrim(patch->>'title'),patch->>'due',COALESCE((patch->>'done')::boolean,false),caller);
     WHEN 'update' THEN
       UPDATE public.mmemo_todos SET
         title=CASE WHEN patch ? 'title' THEN btrim(patch->>'title') ELSE title END,
         due=CASE WHEN patch ? 'due' THEN patch->>'due' ELSE due END,
         done=CASE WHEN patch ? 'done' THEN (patch->>'done')::boolean ELSE done END,
         updated_at=clock_timestamp()
       WHERE id=target AND space_id=shared_space;
       GET DIAGNOSTICS rows_changed=ROW_COUNT;
       IF rows_changed<>1 THEN RAISE EXCEPTION 'Task no longer exists'; END IF;
     WHEN 'delete' THEN
       DELETE FROM public.mmemo_todos WHERE id=target AND space_id=shared_space;
       GET DIAGNOSTICS rows_changed=ROW_COUNT;
       IF rows_changed<>1 THEN RAISE EXCEPTION 'Task no longer exists'; END IF;
     ELSE RAISE EXCEPTION 'Unsupported action';
   END CASE;
 END LOOP;
 RETURN jsonb_build_object('applied',jsonb_array_length(changes));
END;
$$;
REVOKE ALL ON FUNCTION public.mmemo_apply(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mmemo_apply(jsonb) TO authenticated;
