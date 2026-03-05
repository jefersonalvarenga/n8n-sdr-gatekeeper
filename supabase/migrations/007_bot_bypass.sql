-- ============================================================================
-- Migration 007: bot_bypass_attempts em gk_conversations
-- ============================================================================
--
-- Rastreia quantas tentativas de bypass de chatbot de menu foram feitas
-- para cada conversa. Limite máximo = 4 tentativas, em ordem:
--   1. "falar com atendente"
--   2. "humano"
--   3. "gestor"
--   4. "0"
--
-- Quando bot_bypass_attempts >= 4:
--   - conversa → status 'stalled'
--   - lead → status 'failed', error_message = 'chatbot_blocked'
-- ============================================================================

ALTER TABLE gk_conversations
  ADD COLUMN IF NOT EXISTS bot_bypass_attempts SMALLINT NOT NULL DEFAULT 0;

COMMENT ON COLUMN gk_conversations.bot_bypass_attempts IS
  'Número de tentativas de bypass de chatbot de menu.
   Incrementado a cada mensagem enviada para tentar alcançar um humano.
   Frases usadas (em ordem): falar com atendente, humano, gestor, 0.
   Quando >= 4, a conversa é marcada como stalled e o lead como failed.';
