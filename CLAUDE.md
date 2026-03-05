# SDR Gatekeeper — Contexto do Projeto

## Visão Geral

Sistema de SDR automatizado via WhatsApp que aborda clínicas médicas para coletar o contato do decisor (gestor/dono). Integra n8n (orquestração), FastAPI/DSPy (agentes de IA), Evolution API (WhatsApp), Supabase (banco) e Google Maps/Ads signals (enriquecimento de dados).

**Repositório FastAPI (agentes de IA):** `/Users/jefersonalvarenga/Documents/ai-decision-engine`

---

## Arquitetura

```
Cron (n8n Greeting)
  → pick_next_clinic() [Supabase]
  → Evolution API (WhatsApp outbound)
  → gk_leads + gk_conversations criados

Webhook (Evolution API → n8n Inbound)
  → Debounce 4s
  → FastAPI Gatekeeper (DSPy + LLM)
  → Evolution API (resposta)
  → gk_messages salvo
  → Se success: clinic_decisors + reação ❤️
  → Se failed/success: GLM5 avalia conversa → gk_discovered_cases

Cron (n8n Expiration, 8h-18h30 BRT)
  → Stalled (2h-24h sem resposta) → Nudge 1
  → Expired (24h+) → Nudge 2
  → Pending Optout (7d) → mensagem opt-out
  → Archived (3d) → sem mensagem
  → Closed (30d) → sem mensagem
```

---

## Banco de Dados (Supabase)

### Tabelas Principais

**`google_maps_signals`** — dados de enriquecimento das clínicas (fonte de prospecção)
- `place_id`, `name`, `phone_e164`, `rating`, `reviews_count`, `ads_count`
- `ads_group` — agrupamento para o bandit epsilon-greedy
- `is_franchise`, `is_ineligible` — flags de elegibilidade

**`google_ads_signals`** — dados de anúncios Google por clínica

**`gk_leads`** — registro de cada abordagem
- `clinic_phone`, `conversation_id`, `sent_at`
- Status: `created → gathering_decisor → decisor_captured | failed | stalled | expired | pending_optout | archived | closed`

**`gk_conversations`** — estado da conversa WhatsApp
- `remote_jid`, `status`, `paused`, `fastapi_session_id`
- `last_message_at` — usado para detectar inatividade
- `decisor_name`, `decisor_phone`, `decisor_email`
- Status: `greeting_sent → gathering_decisor → decisor_captured | denied | stalled | expired | pending_optout | archived | closed`

**`gk_messages`** — histórico de cada mensagem
- `direction` (inbound/outbound), `content`, `stage`, `conversation_id`

**`gk_events`** — log de eventos importantes
- `event_type`: `stalled_nudge_sent`, `expired_nudge_sent`, `optout_question_sent`, etc.

**`clinic_decisors`** — contatos de decisores capturados
- `place_id`, `name`, `phone`, `email`, `contact_type`

**`gk_discovered_cases`** — avaliações do GLM5 pós-conversa
- `quality_score`, `outcome_label`, `sofia_did_well`, `sofia_should_improve`
- `is_new_pattern`, `suggested_scenario_name`
- Outcome labels: `SUCCESS`, `EMAIL_SUCCESS`, `GRACEFUL_DENIED`, `SLOW_EXIT`, `STUCK`, `BLOCKED_RISK`

**`sdr_config`** — configuração global (id=1)
- `environment`: `production | homolog`
- `homolog_phone` — número para redirecionar em homolog

---

## Workflows n8n

### 1. SDR Gatekeeper - Greeting (Outbound)
**Cron:** `0 */5 8-18 * * *` (a cada 5min, 8h-19h BRT)
**Delay:** 20-30s aleatório

Fluxo:
1. Horário comercial? (8h-19h BRT)
2. Cap diário? (conta `gk_leads` criados hoje em BRT via `DATE_TRUNC`)
3. `pick_next_clinic()` — bandit epsilon-greedy por `ads_group`
4. Verifica Pausa (COALESCE subquery — sempre retorna 1 linha mesmo sem conversa)
5. Seleciona template
6. Envia via Evolution API
7. Cria `gk_leads` (status: `created`) e `gk_conversations` (status: `greeting_sent`)

**Decisões já tomadas:**
- Inbound não aciona mais o outbound (removido em refactor)
- `pick_next_clinic()` exclui TODAS as clínicas já em `gk_leads` (migration 015)

### 2. SDR Gatekeeper - Inbound
**Trigger:** Webhook da Evolution API (`messages.upsert`)

Fluxo:
1. Extrai payload → ignora `fromMe`, grupos, status broadcasts
2. Debounce 4s (compara `wamid`)
3. Verifica Bloqueios (bot bypass cooldown)
4. Verifica Pausa (operador humano assumiu → ignora)
5. Busca conversa no DB
6. Prepara histórico + contexto
7. FastAPI Gatekeeper (DSPy + LLM) → resposta + stage
8. Salva mensagem + atualiza status
9. Envia resposta via Evolution API
10. Se `decisor_captured`: insere `clinic_decisors` + reação ❤️
11. Se `success | failed`: GLM5 avalia conversa → `gk_discovered_cases`

**Bugs corrigidos nesta sessão:**
- `Em Cooldown Bypass?` output 0 estava vazio (mensagens descartadas) → conectado ao Verifica Bloqueios
- `gk_leads` não atualizava para `failed` quando `conversationStage='denied'` → UPDATE adicionado
- Reação ❤️ era enviada em falhas → movida exclusivamente para o caminho `decisor_captured`

### 3. SDR Gatekeeper - Expiração de Conversas
**Cron:** `0 */30 8-18 * * *` (a cada 30min, 8h-18h30 BRT — sem nudges fora do horário)

5 branches paralelos a partir de Supabase - Lê Config:
| Branch | Gatilho | Transição | Mensagem |
|--------|---------|-----------|---------|
| 1 Stalled | 2h–24h sem resposta, status greeting_sent\|gathering_decisor | → stalled | Nudge 1 |
| 2 Expired | 24h+ sem resposta, status greeting_sent\|gathering_decisor\|stalled, paused IS NOT TRUE | → expired | Nudge 2 |
| 3 Pending Optout | 7d após expired | → pending_optout | Msg opt-out |
| 4 Archived | 3d após pending_optout | → archived | Sem mensagem |
| 5 Closed | 30d após archived | → closed | Sem mensagem |

**Bugs corrigidos nesta sessão:**
- Race condition Branch 1 × Branch 2: Branch 1 agora tem teto `>= NOW() - 24h`
- Branch 2 não verificava `paused IS NOT TRUE` → corrigido

---

## Função Bandit — `pick_next_clinic()`

Algoritmo epsilon-greedy por `ads_group`. Exclui clínicas já presentes em `gk_leads` (qualquer status). Migration: `015_pick_next_clinic_exclude_all_leads.sql`.

---

## Variáveis de Ambiente (n8n)

| Var | Uso |
|-----|-----|
| `EVOLUTION_API_URL` | URL da Evolution API |
| `EVOLUTION_INSTANCE_NAME` | Nome da instância WhatsApp |
| `EVOLUTION_API_KEY` | Chave da Evolution API |
| `FASTAPI_API_KEY` | Chave da FastAPI (agentes DSPy) |
| `FASTAPI_BASE_URL` | `https://ade.easyscale.co` |
| `SUPABASE_CREDENTIALS_ID` | ID das credenciais Postgres no n8n |

---

## Regras de Negócio

- **Horário comercial:** 8h–19h BRT (America/Sao_Paulo)
- **Cap diário:** limite de greetings por dia, contado em BRT
- **Pausa:** `paused=true` em `gk_conversations` = operador humano assumiu → bot não interfere
- **Bot bypass cooldown:** 30s após envio de mensagem para menus de bot
- **Debounce:** 4s + comparação de `wamid` para evitar duplicatas

---

## Migrations Supabase (ordem)

001 create_conversations → 002 create_leads → 002 drop_status_constraint → 003 lifecycle_statuses → 004 operator_pause → 005 homolog_cleanup → 006 switch_environment_func → 007 bot_bypass → 008 sdr_name → 009 bot_bypass_cooldown → 010 sdr_debounce → 011 gk_discovered_cases → 012 cleanup_homolog_security_definer → 013 google_maps_signals_is_franchise → 014 google_maps_signals_is_ineligible → **015 pick_next_clinic_exclude_all_leads**

---

## Pendências Conhecidas

- [ ] Nós desativados no inbound: `Evolution - Confirma Reset` — avaliar se reativar
- [ ] `greeting_sent` status: bot não atualiza lead/conversa para este status após envio do greeting (observabilidade)
- [ ] Inbound não re-ativa conversas `stalled`/`expired` quando clínica responde ao nudge
- [ ] Payload da FastAPI não inclui dados de enriquecimento (`rating`, `reviews_count`, `ads_count`) — necessário para recovery inteligente pós-rejeição
