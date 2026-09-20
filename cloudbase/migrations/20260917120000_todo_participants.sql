ALTER TABLE public.mmemo_todos ADD COLUMN participants text[];
UPDATE public.mmemo_todos SET participants=ARRAY[created_by];
ALTER TABLE public.mmemo_todos ALTER COLUMN participants SET NOT NULL;
ALTER TABLE public.mmemo_todos ADD CONSTRAINT mmemo_participants_shape CHECK (
 array_ndims(participants)=1 AND cardinality(participants) BETWEEN 1 AND 2
 AND array_position(participants,NULL) IS NULL
 AND (cardinality(participants)=1 OR participants[1]<>participants[2])
);
CREATE OR REPLACE FUNCTION public.mmemo_apply(changes jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
 caller text := auth.uid();
 shared_space text;
 item jsonb;
 patch jsonb;
 seen text[] := '{}';
 target text;
 rows_changed integer;
 participant_ids text[];
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
     IF jsonb_typeof(patch) IS DISTINCT FROM 'object' OR (patch - ARRAY['title','due','done','participants']) <> '{}'::jsonb THEN RAISE EXCEPTION 'Invalid fields'; END IF;
     IF (patch ? 'title' AND jsonb_typeof(patch->'title') IS DISTINCT FROM 'string') OR
        (patch ? 'due' AND jsonb_typeof(patch->'due') IS DISTINCT FROM 'string') OR
        (patch ? 'done' AND jsonb_typeof(patch->'done') IS DISTINCT FROM 'boolean') THEN RAISE EXCEPTION 'Invalid field types'; END IF;
   END IF;
   IF item->>'action' IN ('create','update') AND patch ? 'participants' THEN
     IF jsonb_typeof(patch->'participants') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Invalid participants'; END IF;
     IF jsonb_array_length(patch->'participants') NOT BETWEEN 1 AND 2 OR EXISTS (
       SELECT 1 FROM jsonb_array_elements(patch->'participants') p WHERE jsonb_typeof(p) <> 'string'
     ) THEN RAISE EXCEPTION 'Expected one or two participant IDs'; END IF;
     SELECT array_agg(value) INTO participant_ids FROM jsonb_array_elements_text(patch->'participants');
     IF (SELECT count(DISTINCT uid) FROM public.mmemo_members WHERE uid=ANY(participant_ids) AND space_id=shared_space) <> cardinality(participant_ids) THEN
       RAISE EXCEPTION 'Participants must be distinct shared-space members';
     END IF;
   ELSE participant_ids := NULL;
   END IF;
   CASE item->>'action'
     WHEN 'create' THEN
       IF NOT (patch ? 'title') OR NOT (patch ? 'due') THEN RAISE EXCEPTION 'Missing fields'; END IF;
       INSERT INTO public.mmemo_todos(id,space_id,title,due,done,created_by,participants)
         VALUES(target,shared_space,btrim(patch->>'title'),patch->>'due',COALESCE((patch->>'done')::boolean,false),caller,COALESCE(participant_ids,ARRAY[caller]));
     WHEN 'update' THEN
       UPDATE public.mmemo_todos SET
         title=CASE WHEN patch ? 'title' THEN btrim(patch->>'title') ELSE title END,
         due=CASE WHEN patch ? 'due' THEN patch->>'due' ELSE due END,
         done=CASE WHEN patch ? 'done' THEN (patch->>'done')::boolean ELSE done END,
         participants=COALESCE(participant_ids,participants),
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
