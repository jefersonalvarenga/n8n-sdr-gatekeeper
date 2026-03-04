-- Migration 003: Full lifecycle statuses
-- Adds new statuses to support the complete expiry cadence:
--   stalled → expired → pending_optout → archived → closed
--   + opted_out (explicit opt-out via response)
--
-- Cadence:
--   2h  sem resposta → stalled    (nudge 1)
--   24h sem resposta → expired    (nudge 2 + ciclo reset)
--   7d  sem resposta → pending_optout (pergunta opt-out)
--   3d  sem resposta → archived   (cooldown 30d)
--   30d sem resposta → closed     (análise manual)

-- -------------------------------------------------------
-- gk_leads: update status constraint
-- -------------------------------------------------------
ALTER TABLE gk_leads DROP CONSTRAINT IF EXISTS gk_leads_status_check;

ALTER TABLE gk_leads
  ADD CONSTRAINT gk_leads_status_check
  CHECK (status IN (
    'created',           -- elegível para o bandit
    'greeting_sent',     -- primeira mensagem enviada
    'gathering_decisor', -- em conversa ativa
    'stalled',           -- 2h sem resposta — nudge 1 enviado
    'expired',           -- 24h sem resposta — nudge 2 enviado
    'pending_optout',    -- 7d sem resposta — perguntou se quer encerrar
    'opted_out',         -- pediu explicitamente para parar (nunca mais contactar)
    'archived',          -- sem resposta ao opt-out — cooldown 30d
    'decisor_captured',  -- contato do decisor coletado (success)
    'failed',            -- recepção negou definitivamente (denied)
    'closed'             -- 30d após archived sem resposta — análise manual
  ));

-- -------------------------------------------------------
-- gk_conversations: sem constraint (removida na 002)
-- Documentar os status válidos via COMMENT
-- -------------------------------------------------------
COMMENT ON COLUMN gk_conversations.status IS
  'Lifecycle statuses:
   Active:  greeting_sent | gathering_decisor | decisor_captured | denied
   Expiry:  stalled (2h) → expired (24h) → pending_optout (7d) → archived (3d) → closed (30d)
   Opt-out: pending_optout → opted_out (resposta explícita)
   Reopen:  qualquer status → gathering_decisor (quando clínica responde)';
