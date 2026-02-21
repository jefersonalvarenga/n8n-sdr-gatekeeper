# Contrato de API - FastAPI Gatekeeper

## Endpoint

```
POST https://ade.easyscale.co/v1/sdr/gatekeeper
```

## Headers

| Header       | Valor                | Obrigatório |
|-------------|----------------------|-------------|
| x-api-key   | `{FASTAPI_API_KEY}`  | Sim         |
| Content-Type | application/json     | Sim         |

## Request Body

```json
{
  "conversation_id": "uuid-da-conversa-no-supabase",
  "remote_jid": "5511999999999@s.whatsapp.net",
  "sender_name": "Maria Recepção",
  "message": "Olá, quem é você?",
  "message_type": "text",
  "phone_number": "5511999999999",
  "is_new_conversation": true,
  "session_id": null
}
```

| Campo              | Tipo    | Descrição                                              |
|-------------------|---------|--------------------------------------------------------|
| conversation_id   | string  | UUID da conversa no Supabase                           |
| remote_jid        | string  | JID completo do WhatsApp                               |
| sender_name       | string  | Push name do WhatsApp (nome do atendente)              |
| message           | string  | Conteúdo da mensagem recebida                          |
| message_type      | string  | `text`, `image`, `audio`, `document`, `reaction`       |
| phone_number      | string  | Número limpo (sem @s.whatsapp.net)                     |
| is_new_conversation | bool  | `true` se é a primeira mensagem desta conversa         |
| session_id        | string? | ID da sessão no FastAPI (null na primeira interação)   |

## Response Body (esperado)

```json
{
  "reply": "Oi Maria! Tudo bem? Sou o João da EasyScale...",
  "session_id": "sess_abc123",
  "intent": "greeting",
  "confidence": 0.95,
  "conversation_status": "active",
  "decisor_info": null
}
```

| Campo               | Tipo    | Descrição                                                    |
|--------------------|---------|--------------------------------------------------------------|
| reply              | string  | Mensagem a ser enviada para o atendente. Vazio = sem resposta |
| session_id         | string  | ID da sessão para manter contexto entre chamadas             |
| intent             | string  | Intenção detectada na mensagem do atendente                  |
| confidence         | float   | Confiança da classificação (0.0 a 1.0)                      |
| conversation_status| string  | Status atualizado da conversa                                |
| decisor_info       | object? | Dados do decisor (quando capturado)                          |

### Valores de `intent`

| Intent              | Descrição                                  |
|--------------------|---------------------------------------------|
| greeting           | Saudação inicial                            |
| asking_who         | Perguntando quem é / o que quer             |
| asking_decisor     | Solicitando contato do decisor              |
| decisor_received   | Atendente informou dados do decisor         |
| objection          | Atendente resistindo / objeção              |
| positive_signal    | Sinal positivo (interesse, abertura)        |
| off_topic          | Mensagem fora do contexto                   |
| rejection          | Rejeição explícita                          |
| unknown            | Não classificável                           |

### Valores de `conversation_status`

| Status            | Descrição                                    |
|-------------------|----------------------------------------------|
| active            | Conversa em andamento                        |
| decisor_captured  | Decisor identificado com sucesso             |
| rejected          | Atendente recusou / bloqueou                 |

### Objeto `decisor_info` (quando presente)

```json
{
  "name": "Dr. Carlos Silva",
  "phone": "5511988887777",
  "email": "carlos@clinica.com",
  "role": "Diretor Clínico"
}
```

Todos os campos são opcionais - o agente preenche conforme o atendente for informando.
