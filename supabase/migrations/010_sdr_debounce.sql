-- ============================================================
-- Migration 010: sdr_debounce — deduplicação de mensagens rápidas
-- ============================================================
-- Problema: quando o atendente envia 2 mensagens em sequência
-- (ex: "oi bom dia" + "em que posso ajudar?"), o Evolution API
-- dispara 2 webhooks quase simultâneos e o SDR responde duas vezes.
--
-- Solução: tabela de debounce.
--   1. Ao receber mensagem, UPSERT remote_jid → wamid mais recente.
--   2. Aguardar 4s (Wait node no n8n).
--   3. Re-consultar: se o wamid registrado ainda é o mesmo → processa.
--      Se for diferente (nova mensagem chegou no intervalo) → descarta.
--
-- A janela de 4s cobre atrasos de digitação rápida sem prejudicar
-- conversas normais (humanos raramente respondem em < 4s).
-- ============================================================

CREATE TABLE IF NOT EXISTS sdr_debounce (
  remote_jid  TEXT        PRIMARY KEY,
  last_wamid  TEXT        NOT NULL,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE sdr_debounce IS
  'Deduplica mensagens rápidas do mesmo contato. '
  'Guarda o wamid mais recente por remote_jid; '
  'execuções concorrentes checam se ainda são as "últimas" após 4s.';

-- Index já existe por ser PK (remote_jid), nenhum index extra necessário.
