-- ============================================================
-- Migration 008: sdr_name em sdr_config
-- ============================================================
-- Adiciona coluna sdr_name à tabela sdr_config para que o nome
-- do agente SDR seja configurável sem alterar código ou env vars.
-- Padrão: 'Vera' (nome feminino consistente com perfil WhatsApp).
-- ============================================================

ALTER TABLE sdr_config
  ADD COLUMN IF NOT EXISTS sdr_name TEXT NOT NULL DEFAULT 'Vera';

COMMENT ON COLUMN sdr_config.sdr_name IS
  'Nome do agente SDR usado para se apresentar na conversa. '
  'Deve ser consistente com o nome/foto do perfil WhatsApp utilizado.';

-- Garante que o registro id=1 já tem o valor padrão
UPDATE sdr_config SET sdr_name = 'Vera' WHERE id = 1 AND sdr_name IS NULL;
