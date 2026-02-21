-- ============================================
-- EasyScale SDR Gatekeeper - Schema
-- Migration 001: Tabelas com prefixo gk_
-- Evita conflito com: conversations, messages, leads (já existentes)
-- ============================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================
-- TABELA: gk_conversations
-- Sessão de conversa do gatekeeper com atendente
-- ============================================
CREATE TABLE IF NOT EXISTS gk_conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Identificação do contato (WhatsApp)
    remote_jid VARCHAR(50) NOT NULL,
    push_name VARCHAR(255),

    -- Contexto da prospecção
    clinic_name VARCHAR(255),

    -- Estado da conversa
    status VARCHAR(30) NOT NULL DEFAULT 'active'
        CHECK (status IN (
            'active',
            'decisor_captured',
            'stalled',
            'rejected',
            'handed_off',
            'expired'
        )),

    -- Dados do decisor (preenchidos quando capturados)
    decisor_name VARCHAR(255),
    decisor_phone VARCHAR(50),
    decisor_email VARCHAR(255),
    decisor_role VARCHAR(100),

    -- Metadata
    evolution_instance VARCHAR(100),
    fastapi_session_id VARCHAR(255),

    -- Contadores
    message_count INTEGER DEFAULT 0,

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_message_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ
);

-- ============================================
-- TABELA: gk_messages
-- Histórico de mensagens do gatekeeper
-- ============================================
CREATE TABLE IF NOT EXISTS gk_messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES gk_conversations(id) ON DELETE CASCADE,

    direction VARCHAR(10) NOT NULL CHECK (direction IN ('inbound', 'outbound')),
    content TEXT NOT NULL,
    message_type VARCHAR(20) DEFAULT 'text'
        CHECK (message_type IN ('text', 'image', 'audio', 'document', 'reaction')),

    wamid VARCHAR(255),

    -- Metadata do agente (para outbound)
    agent_intent VARCHAR(50),
    agent_confidence DECIMAL(3,2),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================
-- TABELA: gk_events
-- Log de eventos do gatekeeper
-- ============================================
CREATE TABLE IF NOT EXISTS gk_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES gk_conversations(id) ON DELETE CASCADE,

    event_type VARCHAR(50) NOT NULL
        CHECK (event_type IN (
            'started',
            'decisor_info_received',
            'followup_sent',
            'stalled_detected',
            'reactivated',
            'handed_off',
            'expired',
            'error'
        )),

    event_data JSONB,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================
-- INDEXES
-- ============================================
CREATE INDEX idx_gk_conversations_remote_jid ON gk_conversations(remote_jid);
CREATE INDEX idx_gk_conversations_status ON gk_conversations(status);
CREATE INDEX idx_gk_conversations_last_message ON gk_conversations(last_message_at);
CREATE INDEX idx_gk_conversations_expires ON gk_conversations(expires_at) WHERE status = 'active';
CREATE INDEX idx_gk_messages_conversation ON gk_messages(conversation_id, created_at);
CREATE INDEX idx_gk_messages_wamid ON gk_messages(wamid);
CREATE INDEX idx_gk_events_conversation ON gk_events(conversation_id, created_at);

-- ============================================
-- TRIGGER: updated_at automático
-- ============================================
CREATE OR REPLACE FUNCTION gk_update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_gk_conversations_updated_at
    BEFORE UPDATE ON gk_conversations
    FOR EACH ROW
    EXECUTE FUNCTION gk_update_updated_at();
