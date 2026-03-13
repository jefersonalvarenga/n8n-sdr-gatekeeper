---
phase: quick-1
plan: 1
type: execute
wave: 1
depends_on: []
files_modified:
  - workflows/sdr-gatekeeper-inbound.json
autonomous: true
requirements:
  - Handle MESSAGES_SET event to update sf_clinics onboarding status
must_haves:
  truths:
    - "Quando a Evolution API envia evento MESSAGES_SET, o workflow executa o UPDATE em sf_clinics"
    - "Eventos que não são MESSAGES_SET continuam fluindo para Parse Evolution Payload sem alteração"
    - "Erro no UPDATE não interrompe o fluxo (continueOnFail: true)"
  artifacts:
    - path: "workflows/sdr-gatekeeper-inbound.json"
      provides: "Nó IF + Supabase UPDATE inseridos e conectados corretamente"
      contains: "MESSAGES_SET"
  key_links:
    - from: "Webhook - Evolution API"
      to: "IF - É MESSAGES_SET?"
      via: "nova conexão main[0]"
    - from: "IF - É MESSAGES_SET?"
      to: "Supabase - Sync Onboarding (MESSAGES_SET)"
      via: "output true (index 0)"
    - from: "IF - É MESSAGES_SET?"
      to: "Parse Evolution Payload"
      via: "output false (index 1)"
---

<objective>
Adicionar tratamento do evento MESSAGES_SET da Evolution API no workflow SDR Gatekeeper - Inbound Handler.

Purpose: Quando a Evolution API reconecta ou sincroniza histórico, ela dispara MESSAGES_SET. Esse evento deve marcar a instância como `sync_complete` na tabela sf_clinics, sem interferir no fluxo normal de mensagens.

Output: Dois novos nós no JSON do workflow — um IF que intercepta MESSAGES_SET logo após o Webhook, e um Supabase/Postgres que executa o UPDATE, com erro silencioso.
</objective>

<execution_context>
@./.claude/get-shit-done/workflows/execute-plan.md
</execution_context>

<context>
@.planning/STATE.md

Workflow alvo: workflows/sdr-gatekeeper-inbound.json

Topologia atual relevante:
- "Webhook - Evolution API" (id: webhook-receiver, posição [250, 300])
  → "Parse Evolution Payload" (id: parse-evolution-payload, posição [480, 300])
  → "Deve Processar?" (id: check-should-process, posição [700, 300])

Nós Supabase existentes usam:
  type: "n8n-nodes-base.postgres"
  typeVersion: 2.5
  credentials: { postgres: { id: "SUPABASE_CREDENTIALS_ID", name: "Postgres SDR Gatekeeper" } }

Payload da Evolution API no webhook:
  $json.body.event  — string com o tipo do evento (ex: "MESSAGES_SET", "messages.upsert")
  $json.body.instance — nome da instância Evolution (usado no WHERE da query)
</context>

<tasks>

<task type="auto">
  <name>Task 1: Inserir nó IF e nó Supabase UPDATE no JSON do workflow</name>
  <files>workflows/sdr-gatekeeper-inbound.json</files>
  <action>
Ler o arquivo workflows/sdr-gatekeeper-inbound.json como JSON. Fazer as seguintes modificações:

**1. Adicionar dois novos nós ao array `nodes`:**

Nó A — IF que verifica MESSAGES_SET:
```json
{
  "parameters": {
    "conditions": {
      "options": {
        "caseSensitive": true,
        "leftValue": "",
        "typeValidation": "strict"
      },
      "conditions": [
        {
          "id": "condition-messages-set",
          "leftValue": "={{ $json.body.event }}",
          "rightValue": "MESSAGES_SET",
          "operator": {
            "type": "string",
            "operation": "equals"
          }
        }
      ],
      "combinator": "and"
    },
    "options": {}
  },
  "id": "check-messages-set",
  "name": "É MESSAGES_SET?",
  "type": "n8n-nodes-base.if",
  "typeVersion": 2,
  "position": [480, 500]
}
```

Nó B — Supabase UPDATE em sf_clinics:
```json
{
  "parameters": {
    "operation": "executeQuery",
    "query": "UPDATE sf_clinics\nSET onboarding_status = 'sync_complete', onboarding_step = 3\nWHERE evolution_instance_id = '{{ $json.body.instance }}'\nAND onboarding_status = 'pending'",
    "options": {}
  },
  "id": "sync-onboarding-messages-set",
  "name": "Supabase - Sync Onboarding (MESSAGES_SET)",
  "type": "n8n-nodes-base.postgres",
  "typeVersion": 2.5,
  "position": [700, 500],
  "credentials": {
    "postgres": {
      "id": "SUPABASE_CREDENTIALS_ID",
      "name": "Postgres SDR Gatekeeper"
    }
  },
  "onError": "continueRegularOutput"
}
```

**2. Atualizar a seção `connections`:**

Remover a conexão direta de "Webhook - Evolution API" para "Parse Evolution Payload":
```json
"Webhook - Evolution API": {
  "main": [
    [
      { "node": "Parse Evolution Payload", "type": "main", "index": 0 }
    ]
  ]
}
```

Substituir por:
```json
"Webhook - Evolution API": {
  "main": [
    [
      { "node": "É MESSAGES_SET?", "type": "main", "index": 0 }
    ]
  ]
}
```

Adicionar conexões para os dois novos nós:
```json
"É MESSAGES_SET?": {
  "main": [
    [
      { "node": "Supabase - Sync Onboarding (MESSAGES_SET)", "type": "main", "index": 0 }
    ],
    [
      { "node": "Parse Evolution Payload", "type": "main", "index": 0 }
    ]
  ]
},
"Supabase - Sync Onboarding (MESSAGES_SET)": {
  "main": [
    []
  ]
}
```

Output true (index 0) do IF = MESSAGES_SET confirmado → vai para o Supabase UPDATE (e para aí).
Output false (index 1) do IF = qualquer outro evento → continua para Parse Evolution Payload (fluxo original).

Salvar o arquivo preservando toda a estrutura JSON existente.

Nota sobre onError: "continueRegularOutput" faz o nó Supabase emitir output mesmo em erro, impedindo que falhas quebrem o fluxo (equivalente a continueOnFail no n8n).
  </action>
  <verify>
    <automated>
      python3 -c "
import json
with open('workflows/sdr-gatekeeper-inbound.json') as f:
    wf = json.load(f)
node_ids = [n['id'] for n in wf['nodes']]
node_names = [n['name'] for n in wf['nodes']]
conns = wf['connections']

# Verifica novos nós presentes
assert 'check-messages-set' in node_ids, 'FALHOU: nó check-messages-set ausente'
assert 'sync-onboarding-messages-set' in node_ids, 'FALHOU: nó sync-onboarding-messages-set ausente'

# Verifica onError no Supabase
supabase_node = next(n for n in wf['nodes'] if n['id'] == 'sync-onboarding-messages-set')
assert supabase_node.get('onError') == 'continueRegularOutput', 'FALHOU: onError não configurado'

# Verifica conexão Webhook → IF
webhook_conns = conns['Webhook - Evolution API']['main'][0]
assert any(c['node'] == 'É MESSAGES_SET?' for c in webhook_conns), 'FALHOU: Webhook não conecta ao IF'

# Verifica IF output false → Parse Evolution Payload
if_false = conns['É MESSAGES_SET?']['main'][1]
assert any(c['node'] == 'Parse Evolution Payload' for c in if_false), 'FALHOU: IF false não conecta ao Parse Evolution Payload'

# Verifica IF output true → Supabase UPDATE
if_true = conns['É MESSAGES_SET?']['main'][0]
assert any(c['node'] == 'Supabase - Sync Onboarding (MESSAGES_SET)' for c in if_true), 'FALHOU: IF true não conecta ao Supabase UPDATE'

# Verifica JSON válido (já garantido pelo parse acima)
print('OK: todas as verificações passaram')
"
    </automated>
  </verify>
  <done>
    - Nó "É MESSAGES_SET?" presente no JSON com condição correta em $json.body.event
    - Nó "Supabase - Sync Onboarding (MESSAGES_SET)" presente com a query UPDATE exata e onError: continueRegularOutput
    - Webhook conectado ao IF (não mais diretamente ao Parse Evolution Payload)
    - IF output true → Supabase UPDATE → fim (sem saída)
    - IF output false → Parse Evolution Payload → fluxo original inalterado
    - JSON do arquivo é válido e parseável
  </done>
</task>

</tasks>

<verification>
Após execução, importar o workflow no n8n e verificar visualmente:
1. Novo nó "É MESSAGES_SET?" aparece entre Webhook e Parse Evolution Payload
2. Output true (verde) do IF conecta ao "Supabase - Sync Onboarding (MESSAGES_SET)"
3. Output false (vermelho) do IF conecta ao "Parse Evolution Payload" existente
4. Nó Supabase tem "Continue on fail" marcado (onError: continueRegularOutput)

Teste funcional (opcional, requer Evolution API):
- Simular POST no webhook com body: `{"event": "MESSAGES_SET", "instance": "nome-da-instancia"}`
- Confirmar que o UPDATE é executado em sf_clinics
- Simular POST com `{"event": "messages.upsert", ...}` — deve ignorar o novo branch e seguir o fluxo normal
</verification>

<success_criteria>
- workflow JSON válido após modificação (sem erro de parse)
- Evento MESSAGES_SET interceptado antes do Parse Evolution Payload
- Query UPDATE usa evolution_instance_id = $json.body.instance e filtra AND onboarding_status = 'pending'
- Falha no Supabase não propaga erro para outros branches do fluxo
- Todos os outros eventos continuam para Parse Evolution Payload sem alteração
</success_criteria>

<output>
Após conclusão, atualizar .planning/STATE.md adicionando esta tarefa na tabela "Quick Tasks Completed":
| 1 | Adicionar handler MESSAGES_SET no inbound (IF + Supabase UPDATE sf_clinics) | 2026-03-13 | {commit_hash} | .planning/quick/1-no-workflow-do-n8n-sofia-inbound-whatsap |
</output>
