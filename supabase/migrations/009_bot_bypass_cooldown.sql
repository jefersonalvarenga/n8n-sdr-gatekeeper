-- ============================================================
-- Migration 009: bot_bypass_cooldown_until em gk_conversations
-- ============================================================
-- Após o SDR enviar uma frase de bypass para um chatbot de menu
-- (ex: "falar com atendente"), o bot responde com mensagens de
-- transição ("Aguarde, estou transferindo..."). Essas mensagens
-- chegam antes do humano assumir o atendimento.
--
-- Este campo registra até quando ignorar mensagens entrantes
-- após o envio de um bypass — evitando que o SDR responda ao
-- próprio bot em loop.
--
-- Uso: quando message_received_at < bot_bypass_cooldown_until
--      → ignorar a mensagem (ainda é o bot respondendo ao bypass)
--      quando message_received_at >= bot_bypass_cooldown_until
--      → processar normalmente (humano assumiu)
-- ============================================================

ALTER TABLE gk_conversations
  ADD COLUMN IF NOT EXISTS bot_bypass_cooldown_until TIMESTAMPTZ;

COMMENT ON COLUMN gk_conversations.bot_bypass_cooldown_until IS
  'Timestamp até o qual mensagens entrantes devem ser ignoradas após envio '
  'de frase de bypass ao chatbot. Evita loop: SDR → bot transition → SDR → ...';
