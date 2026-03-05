-- ============================================================
-- Migration 012: gk_cleanup_homolog() com SECURITY DEFINER
-- ============================================================
-- A função era chamada pelo n8n (role anônima/service) que não
-- tem permissão direta em clinic_decisors.
-- SECURITY DEFINER faz a função rodar com os privilégios do
-- owner do schema (postgres/supabase_admin), contornando o
-- "permission denied for table clinic_decisors".
--
-- Mesmo padrão aplicado em gk_switch_environment() (migration 006).
-- ============================================================

CREATE OR REPLACE FUNCTION gk_cleanup_homolog()
RETURNS TABLE (
  deleted_conversations    INT,
  deleted_discovered_cases INT,
  deleted_decisors         INT,
  reset_leads              INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_conv  INT := 0;
  v_cases INT := 0;
  v_dec   INT := 0;
  v_leads INT := 0;
BEGIN
  -- Captura remote_jids e place_ids ANTES de qualquer deleção
  CREATE TEMP TABLE _h_jids ON COMMIT DROP AS
    SELECT remote_jid FROM gk_conversations WHERE is_homolog = true;

  CREATE TEMP TABLE _h_places ON COMMIT DROP AS
    SELECT DISTINCT place_id FROM gk_leads WHERE is_homolog = true;

  -- 1. Zera FK conversation_id nos leads ANTES de deletar conversas
  UPDATE gk_leads
    SET conversation_id = NULL
  WHERE is_homolog = true;

  -- 2. Deleta conversas de homolog
  --    CASCADE automático → gk_messages, gk_events
  --    SET NULL automático → gk_discovered_cases.conversation_id
  DELETE FROM gk_conversations WHERE is_homolog = true;
  GET DIAGNOSTICS v_conv = ROW_COUNT;

  -- 3. Deleta gk_discovered_cases pelo remote_jid
  DELETE FROM gk_discovered_cases
  WHERE remote_jid IN (SELECT remote_jid FROM _h_jids);
  GET DIAGNOSTICS v_cases = ROW_COUNT;

  -- 4. Deleta clinic_decisors pelo place_id
  --    CASCADE automático → closer_conversations → closer_messages
  DELETE FROM clinic_decisors
  WHERE place_id IN (SELECT place_id FROM _h_places);
  GET DIAGNOSTICS v_dec = ROW_COUNT;

  -- 5. Reseta leads de homolog → 'created'
  UPDATE gk_leads
  SET status          = 'created',
      conversation_id = NULL,
      sent_at         = NULL,
      error_message   = NULL,
      retry_count     = 0,
      is_homolog      = false,
      updated_at      = NOW()
  WHERE is_homolog = true;
  GET DIAGNOSTICS v_leads = ROW_COUNT;

  RETURN QUERY SELECT v_conv, v_cases, v_dec, v_leads;
END;
$$;

COMMENT ON FUNCTION gk_cleanup_homolog() IS
  'Remove todos os dados gerados durante rodadas de homologação e reseta leads
   para "created". SECURITY DEFINER: roda com privilégios do owner do schema.

   Inclui:
     - gk_conversations (CASCADE: gk_messages, gk_events)
     - gk_discovered_cases (por remote_jid)
     - clinic_decisors (CASCADE: closer_conversations, closer_messages)
   Leads de homolog são resetados para status=created e is_homolog=false.

   Uso: SELECT * FROM gk_cleanup_homolog();';
