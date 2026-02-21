-- ============================================
-- EasyScale SDR Closer - Schema de Conversas
-- Migration 001: Tabelas principais
-- ============================================

-- Extensão para UUID
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================
-- TABELA: conversations
-- Representa uma sessão de conversa com um atendente
-- ============================================
CREATE TABLE IF NOT EXISTS conversations (
    id UUID PRIMARY KEY DEFAULT uuid_ossp.uuid_generate_v4(),

    -- Identificação do contato (WhatsApp)
    remote_jid VARCHAR(50) NOT NULL,          -- número do atendente (5511999999999@s.whatsapp.net)
    push_name VARCHAR(255),                    -- nome do atendente no WhatsApp

    -- Contexto da prospecção
    clinic_name VARCHAR(255),                  -- nome da clínica sendo prospectada

    -- Estado da conversa
    status VARCHAR(30) NOT NULL DEFAULT 'active'
        CHECK (status IN (
            'active',              -- conversa em andamento
            'decisor_captured',    -- decisor identificado com sucesso
            'stalled',             -- atendente parou de responder
            'rejected',            -- atendente recusou/bloqueou
            'handed_off',          -- passado pra closer
            'expired'              -- timeout (sem resposta por X horas)
        )),

    -- Dados do decisor (preenchidos quando capturados)
    decisor_name VARCHAR(255),
    decisor_phone VARCHAR(50),
    decisor_email VARCHAR(255),
    decisor_role VARCHAR(100),                 -- cargo do decisor

    -- Metadata
    evolution_instance VARCHAR(100),           -- instância da Evolution API
    fastapi_session_id VARCHAR(255),           -- ID da sessão no FastAPI (se houver)

    -- Contadores
    message_count INTEGER DEFAULT 0,

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_message_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ                     -- quando a conversa expira por inatividade
);

-- ============================================
-- TABELA: messages
-- Histórico de mensagens trocadas
-- ============================================
CREATE TABLE IF NOT EXISTS messages (
    id UUID PRIMARY KEY DEFAULT uuid_ossp.uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,

    -- Direção e conteúdo
    direction VARCHAR(10) NOT NULL CHECK (direction IN ('inbound', 'outbound')),
    content TEXT NOT NULL,
    message_type VARCHAR(20) DEFAULT 'text'
        CHECK (message_type IN ('text', 'image', 'audio', 'document', 'reaction')),

    -- IDs externos
    wamid VARCHAR(255),                        -- WhatsApp Message ID (da Evolution API)

    -- Metadata do agente (para outbound)
    agent_intent VARCHAR(50),                  -- intenção detectada pelo agente
    agent_confidence DECIMAL(3,2),             -- confiança da classificação (0.00 a 1.00)

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================
-- TABELA: conversation_events
-- Log de eventos importantes da conversa
-- ============================================
CREATE TABLE IF NOT EXISTS conversation_events (
    id UUID PRIMARY KEY DEFAULT uuid_ossp.uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,

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

    event_data JSONB,                          -- dados adicionais do evento

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================
-- INDEXES
-- ============================================
CREATE INDEX idx_conversations_remote_jid ON conversations(remote_jid);
CREATE INDEX idx_conversations_status ON conversations(status);
CREATE INDEX idx_conversations_last_message ON conversations(last_message_at);
CREATE INDEX idx_conversations_expires ON conversations(expires_at) WHERE status = 'active';
CREATE INDEX idx_messages_conversation ON messages(conversation_id, created_at);
CREATE INDEX idx_messages_wamid ON messages(wamid);
CREATE INDEX idx_events_conversation ON conversation_events(conversation_id, created_at);

-- ============================================
-- TRIGGER: Atualiza updated_at automaticamente
-- ============================================
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_conversations_updated_at
    BEFORE UPDATE ON conversations
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

-- ============================================
-- RLS (Row Level Security) - Supabase
-- Habilitar se for usar via Supabase client
-- ============================================
-- ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE conversation_events ENABLE ROW LEVEL SECURITY;
