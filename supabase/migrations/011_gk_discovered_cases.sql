-- ============================================================
-- Migration 011: gk_discovered_cases
-- ============================================================
-- Tabela de avaliações de conversas encerradas pelo GLM.
-- Alimentada pelo pipeline:
--   Conversa Encerrada? → Supabase - Histórico Completo
--   → Code - Monta Prompt GLM → HTTP - GLM Avalia Conversa
--   → Code - Processa Resposta GLM → Supabase - Salva Descoberta
--
-- Usada pelo auto-tune (auto_tune_from_real.py) para:
--   1. Gerar novos casos de teste a partir de falhas reais
--   2. Gerar patch de melhoria para a GatekeeperSignature
-- ============================================================

CREATE TABLE IF NOT EXISTS gk_discovered_cases (
  id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id         UUID        REFERENCES gk_conversations(id) ON DELETE SET NULL,
  remote_jid              TEXT,
  clinic_name             TEXT,

  -- Resultado da conversa
  final_stage             TEXT,       -- opening | requesting | handling_objection | success | failed
  quality_score           NUMERIC(4, 3) CHECK (quality_score >= 0 AND quality_score <= 1),
  outcome_label           TEXT,       -- SUCCESS | EMAIL_SUCCESS | GRACEFUL_DENIED | SLOW_EXIT | STUCK | BLOCKED_RISK

  -- Análise do GLM
  outcome_reason          TEXT,
  sofia_did_well          JSONB       DEFAULT '[]'::jsonb,
  sofia_should_improve    JSONB       DEFAULT '[]'::jsonb,
  is_new_pattern          BOOLEAN     NOT NULL DEFAULT false,
  suggested_scenario_name TEXT,

  -- Raw data para auditoria e re-treinamento
  full_conversation       TEXT,
  raw_glm_response        TEXT,

  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Índices para as queries do auto-tune
CREATE INDEX IF NOT EXISTS idx_discovered_cases_quality
  ON gk_discovered_cases (quality_score, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_discovered_cases_new_pattern
  ON gk_discovered_cases (is_new_pattern, created_at DESC)
  WHERE is_new_pattern = true;

COMMENT ON TABLE gk_discovered_cases IS
  'Avaliações de conversas reais feitas pelo GLM ao encerrar cada conversa. '
  'Base de dados para o pipeline de auto-tune da GatekeeperSignature.';
