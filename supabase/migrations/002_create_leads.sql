-- ============================================
-- Migration 002: Tabela gk_leads + Função ICP
-- Pipeline de leads para outbound greeting
-- ============================================

CREATE TABLE IF NOT EXISTS gk_leads (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Identificação do lead
    clinic_name VARCHAR(255) NOT NULL,
    clinic_phone VARCHAR(50) NOT NULL,
    remote_jid VARCHAR(60) GENERATED ALWAYS AS (clinic_phone || '@s.whatsapp.net') STORED,

    -- Origem
    source VARCHAR(50) DEFAULT 'supabase_func',

    -- Status do envio
    status VARCHAR(30) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'sent', 'failed', 'skipped')),

    -- Timestamps de envio
    sent_at TIMESTAMPTZ,

    -- Link com conversa criada
    conversation_id UUID REFERENCES gk_conversations(id),

    -- Error tracking
    error_message TEXT,
    retry_count INTEGER DEFAULT 0,

    -- Dados extras (flexível)
    extra_data JSONB,

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================
-- INDEXES
-- ============================================
CREATE UNIQUE INDEX idx_gk_leads_phone ON gk_leads(clinic_phone);
CREATE INDEX idx_gk_leads_status ON gk_leads(status);
CREATE INDEX idx_gk_leads_pending ON gk_leads(created_at) WHERE status = 'pending';

-- ============================================
-- TRIGGER: updated_at automático
-- ============================================
CREATE TRIGGER trigger_gk_leads_updated_at
    BEFORE UPDATE ON gk_leads
    FOR EACH ROW
    EXECUTE FUNCTION gk_update_updated_at();

-- ============================================
-- FUNÇÃO: retorna próximos leads ICP para contactar
-- Exclui leads que já têm conversa ativa
-- ============================================
CREATE OR REPLACE FUNCTION gk_get_pending_leads(batch_limit INT DEFAULT 10)
RETURNS TABLE (
    id UUID,
    clinic_name VARCHAR,
    clinic_phone VARCHAR,
    remote_jid VARCHAR
) AS $$
BEGIN
    RETURN QUERY
    SELECT l.id, l.clinic_name, l.clinic_phone, l.remote_jid
    FROM gk_leads l
    WHERE l.status = 'pending'
      AND l.retry_count < 3
      AND NOT EXISTS (
          SELECT 1 FROM gk_conversations c
          WHERE c.remote_jid = l.remote_jid
            AND c.status IN ('active', 'stalled', 'decisor_captured')
      )
    ORDER BY l.created_at ASC
    LIMIT batch_limit;
END;
$$ LANGUAGE plpgsql;
