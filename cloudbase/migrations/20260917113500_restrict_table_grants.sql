-- CloudBase default privileges grant table writes; restrict these RPC-owned tables explicitly.
REVOKE ALL ON public.mmemo_members, public.mmemo_todos FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.mmemo_members, public.mmemo_todos TO authenticated;
