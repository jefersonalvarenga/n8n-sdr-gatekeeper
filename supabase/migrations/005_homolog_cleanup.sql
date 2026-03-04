-- ============================================================================
-- Migration 005: is_homolog + gk_cleanup_homolog()
-- ============================================================================
--
-- Permite identificar registros criados durante rodadas de homologação e
-- limpá-los antes de ir para produção (ou entre rodadas de teste).
--
-- Tabelas que recebem is_homolog: gk_conversations e gk_leads.
-- As demais tabelas são limpas via CASCADE ou por lookup de remote_jid / place_id:
--
--   gk_conversations (is_homolog=true)
--     → CASCADE: gk_messages, gk_events
--     → SET NULL: gk_discovered_cases.conversation_id  (identificar por remote_jid)
--
--   gk_leads (is_homolog=true)  ── place_id (FK lógica) ──→ clinic_decisors
--                                                                 → CASCADE: closer_conversations
--                                                                              → CASCADE: closer_messages
--
-- DEPENDÊNCIAS: 001_create_conversations.sql, 002_create_leads.sql
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Colunas
-- ----------------------------------------------------------------------------
ALTER TABLE gk_conversations
  ADD COLUMN IF NOT EXISTS is_homolog BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE gk_leads
  ADD COLUMN IF NOT EXISTS is_homolog BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN gk_conversations.is_homolog IS
  'true = criado durante rodada de homologação. Limpar com gk_cleanup_homolog()';
COMMENT ON COLUMN gk_leads.is_homolog IS
  'true = abordado durante rodada de homologação. Resetar com gk_cleanup_homolog()';

-- Índices parciais para cleanup eficiente (só indexa as linhas true)
CREATE INDEX IF NOT EXISTS idx_gk_conversations_homolog
  ON gk_conversations(is_homolog) WHERE is_homolog = true;

CREATE INDEX IF NOT EXISTS idx_gk_leads_homolog
  ON gk_leads(is_homolog) WHERE is_homolog = true;

-- ----------------------------------------------------------------------------
-- Função de cleanup — respeita cadeia de FKs
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION gk_cleanup_homolog()
RETURNS TABLE (
  deleted_conversations    INT,
  deleted_discovered_cases INT,
  deleted_decisors         INT,   -- cascade automático: closer_conversations + closer_messages
  reset_leads              INT
)
LANGUAGE plpgsql AS $$
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
  --    (gk_leads.conversation_id não tem ON DELETE CASCADE — precisa ser explícito)
  UPDATE gk_leads
    SET conversation_id = NULL
  WHERE is_homolog = true;

  -- 2. Deleta conversas de homolog
  --    CASCADE automático → gk_messages, gk_events
  --    SET NULL automático → gk_discovered_cases.conversation_id
  DELETE FROM gk_conversations WHERE is_homolog = true;
  GET DIAGNOSTICS v_conv = ROW_COUNT;

  -- 3. Deleta gk_discovered_cases pelo remote_jid
  --    (ON DELETE SET NULL não apaga a linha — precisamos fazer explicitamente)
  DELETE FROM gk_discovered_cases
  WHERE remote_jid IN (SELECT remote_jid FROM _h_jids);
  GET DIAGNOSTICS v_cases = ROW_COUNT;

  -- 4. Deleta clinic_decisors pelo place_id
  --    CASCADE automático → closer_conversations → closer_messages
  DELETE FROM clinic_decisors
  WHERE place_id IN (SELECT place_id FROM _h_places);
  GET DIAGNOSTICS v_dec = ROW_COUNT;

  -- 5. Reseta leads de homolog → 'created' (elegíveis novamente para o bandit)
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
   para "created". Inclui:
     - gk_conversations (CASCADE: gk_messages, gk_events)
     - gk_discovered_cases (por remote_jid)
     - clinic_decisors (CASCADE: closer_conversations, closer_messages)
   Leads de homolog são resetados para status=created e is_homolog=false.

   Uso: SELECT * FROM gk_cleanup_homolog();

   Normalmente disparado pelo workflow sdr-admin-activate-production antes
   de mudar sdr_config.environment para production.';
