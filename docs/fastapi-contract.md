# Contrato de API - FastAPI Gatekeeper

## Endpoint

```
POST https://ade.easyscale.co/v1/sdr/gatekeeper
```

## Headers

| Header       | Valor                | Obrigatório |
|-------------|----------------------|-------------|
| X-API-Key   | `{FASTAPI_API_KEY}`  | Sim         |
| Content-Type | application/json     | Sim         |

## Request Body

```json
{
  "clinic_name": "Clínica Exemplo",
  "clinic_phone": "5511999999999",
  "conversation_history": [
    { "role": "attendant", "content": "Olá, quem é você?" },
    { "role": "agent", "content": "Oi! Sou o João da EasyScale..." },
    { "role": "attendant", "content": "Ah sim, o que precisa?" }
  ],
  "latest_message": "Ah sim, o que precisa?"
}
```

| Campo                | Tipo     | Descrição                                                    |
|---------------------|----------|--------------------------------------------------------------|
| clinic_name         | string   | Nome da clínica (pode ser vazio na primeira interação)       |
| clinic_phone        | string   | Telefone da clínica (número limpo, sem @s.whatsapp.net)      |
| conversation_history| array    | Histórico de mensagens: `[{ role, content }]`                |
| latest_message      | string?  | Última mensagem recebida (opcional)                          |

### Objeto `conversation_history[]`

| Campo   | Tipo   | Valores                       |
|---------|--------|-------------------------------|
| role    | string | `"attendant"` ou `"agent"`    |
| content | string | Conteúdo da mensagem          |

## Response Body

```json
{
  "response_message": "Oi! Tudo bem? Sou o João da EasyScale...",
  "should_send_message": true,
  "conversation_stage": "active",
  "extracted_manager_contact": null,
  "extracted_manager_name": null
}
```

| Campo                    | Tipo    | Descrição                                                    |
|-------------------------|---------|--------------------------------------------------------------|
| response_message        | string  | Mensagem a ser enviada para o atendente                      |
| should_send_message     | boolean | Se `true`, enviar `response_message` via WhatsApp            |
| conversation_stage      | string  | Estágio atual da conversa                                    |
| extracted_manager_contact| string? | Contato do decisor/gestor extraído (telefone, email, etc.)  |
| extracted_manager_name  | string? | Nome do decisor/gestor extraído                              |

### Valores de `conversation_stage`

| Stage              | Descrição                                    |
|-------------------|----------------------------------------------|
| active            | Conversa em andamento                        |
| decisor_captured  | Decisor identificado com sucesso             |
| rejected          | Atendente recusou / bloqueou                 |
| stalled           | Conversa travada / sem resposta              |

## Variáveis de Ambiente Necessárias (n8n)

| Variável          | Descrição                           |
|-------------------|-------------------------------------|
| FASTAPI_API_KEY   | Chave de acesso à API FastAPI       |
| FASTAPI_BASE_URL  | URL base (https://ade.easyscale.co) |
