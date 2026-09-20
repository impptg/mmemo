CREATE TABLE public.mmemo_hearts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sender text NOT NULL REFERENCES public.mmemo_members(uid),
  recipient text NOT NULL REFERENCES public.mmemo_members(uid),
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (sender <> recipient)
);
CREATE INDEX mmemo_hearts_recipient ON public.mmemo_hearts(recipient,created_at,id);
ALTER TABLE public.mmemo_hearts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.mmemo_hearts FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.mmemo_hearts TO authenticated;
CREATE POLICY own_hearts ON public.mmemo_hearts FOR SELECT TO authenticated
  USING (recipient=auth.uid());

CREATE FUNCTION public.mmemo_send_heart() RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE caller text := auth.uid(); peer text;
BEGIN
  SELECT other.uid INTO STRICT peer FROM public.mmemo_members me
    JOIN public.mmemo_members other ON other.space_id=me.space_id AND other.uid<>me.uid
    WHERE me.uid=caller;
  INSERT INTO public.mmemo_hearts(sender,recipient) VALUES(caller,peer);
END;
$$;
CREATE FUNCTION public.mmemo_ack_hearts(ids uuid[]) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path=public,pg_temp AS $$
  DELETE FROM public.mmemo_hearts WHERE recipient=auth.uid() AND id=ANY(ids);
$$;
REVOKE ALL ON FUNCTION public.mmemo_send_heart(), public.mmemo_ack_hearts(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mmemo_send_heart(), public.mmemo_ack_hearts(uuid[]) TO authenticated;
