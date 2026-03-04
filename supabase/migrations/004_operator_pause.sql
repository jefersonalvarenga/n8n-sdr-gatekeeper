-- ============================================================================
-- Migration 004: Operator Pause — coluna paused em gk_conversations
-- ============================================================================
--
-- Quando o operador envia uma mensagem diretamente pelo app do WhatsApp
-- (fromMe: true), o workflow define paused = true e o bot para de responder.
-- Para reativar a IA, basta setar paused = false via Supabase ou painel.
--
-- DEPENDÊNCIAS: 001_create_conversations.sql (gk_conversations já existe)
-- ============================================================================

ALTER TABLE gk_conversations
  ADD COLUMN IF NOT EXISTS paused    BOOLEAN     DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS paused_at TIMESTAMPTZ;

COMMENT ON COLUMN gk_conversations.paused    IS 'true = operador assumiu o chat, IA para de responder';
COMMENT ON COLUMN gk_conversations.paused_at IS 'timestamp do último paused = true pelo operador';

-- Índice para filtrar conversas pausadas rapidamente
CREATE INDEX IF NOT EXISTS idx_gk_conversations_paused
  ON gk_conversations(paused)
  WHERE paused = true;
