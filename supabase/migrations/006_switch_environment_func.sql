-- ============================================================================
-- Migration 006: gk_switch_environment() — SECURITY DEFINER
-- ============================================================================
--
-- O nó Postgres do n8n conecta como um usuário que não tem GRANT de UPDATE
-- na tabela sdr_config (que pertence ao schema de ai-decision-engine e só
-- concede permissões para anon e service_role).
--
-- SECURITY DEFINER faz a função executar com os privilégios do criador
-- (postgres/superuser), contornando o problema sem alterar grants globais.
--
-- Chamada pelo workflow sdr-admin-switch-environment.
-- ============================================================================

CREATE OR REPLACE FUNCTION gk_switch_environment(
  p_environment   TEXT,
  p_homolog_phone TEXT DEFAULT NULL
)
RETURNS TABLE (
  out_environment   TEXT,
  out_homolog_phone TEXT,
  out_updated_at    TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF p_environment NOT IN ('homolog', 'production') THEN
    RAISE EXCEPTION 'environment deve ser ''homolog'' ou ''production''';
  END IF;

  RETURN QUERY
  UPDATE sdr_config
  SET environment   = p_environment,
      -- Atualiza homolog_phone somente se um valor não-vazio foi passado
      homolog_phone = COALESCE(NULLIF(p_homolog_phone, ''), homolog_phone),
      updated_at    = NOW()
  WHERE id = 1
  RETURNING
    environment::TEXT,
    homolog_phone::TEXT,
    updated_at;
END;
$$;

COMMENT ON FUNCTION gk_switch_environment(TEXT, TEXT) IS
  'Alterna sdr_config.environment entre ''homolog'' e ''production''.
   Usa SECURITY DEFINER para contornar restrições de GRANT no n8n.
   homolog_phone é opcional: omitir mantém o número atual.
   Uso: SELECT * FROM gk_switch_environment(''production'');
         SELECT * FROM gk_switch_environment(''homolog'', ''5511999990000'');';
