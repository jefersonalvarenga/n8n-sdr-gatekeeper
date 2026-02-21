# GitOps Setup - Deploy Automático GitHub → n8n

## Como funciona

```
Push em main (pasta workflows/)
  → GitHub Webhook
  → n8n recebe
  → Baixa JSON do GitHub
  → Cria ou atualiza workflow via API do n8n
```

## Pré-requisitos

### 1. Habilitar API do n8n

No `.env` do seu n8n (ou docker-compose), adicione:

```env
N8N_API_ENABLED=true
N8N_API_KEY=gere-uma-chave-segura-aqui
```

Reinicie o n8n após a alteração.

### 2. Importar o workflow deployer manualmente (primeira vez)

Este é o único workflow que precisa ser importado manualmente:

1. Acesse `https://n8n.easyscale.co`
2. Vá em **Workflows → Import from File**
3. Selecione `workflows/gitops-deployer.json`
4. **Ative o workflow** (toggle ON)

> Após isso, todos os outros workflows serão deployados automaticamente via push.

### 3. Configurar Webhook no GitHub

1. Vá em: `https://github.com/jefersonalvarenga/n8n-sdr-gatekeeper/settings/hooks`
2. Clique **Add webhook**
3. Configure:

| Campo          | Valor                                                    |
|---------------|----------------------------------------------------------|
| Payload URL   | `https://n8n.easyscale.co/webhook/gitops-deploy`         |
| Content type  | `application/json`                                       |
| Secret        | _(opcional, mas recomendado)_                            |
| Events        | Selecione **Just the push event**                        |
| Active        | ✅ Marcado                                                |

4. Clique **Add webhook**

### 4. Configurar variável de ambiente no n8n

Certifique-se de que `N8N_API_KEY` está disponível como variável de ambiente no n8n.

## Fluxo de uso

```bash
# 1. Edite um workflow JSON localmente
vim workflows/sdr-gatekeeper-inbound.json

# 2. Commit e push
git add workflows/sdr-gatekeeper-inbound.json
git commit -m "fix: ajusta timeout do FastAPI"
git push origin main

# 3. Pronto! O n8n atualiza automaticamente em ~5 segundos
```

## Proteções

- **Só processa push na branch `main`** - branches de feature não trigam deploy
- **Só processa arquivos em `workflows/*.json`** - outros arquivos são ignorados
- **Ignora `gitops-deployer.json`** - evita loop infinito
- **Create vs Update automático** - detecta se o workflow já existe pelo nome

## Troubleshooting

### Webhook não chega no n8n
- Verifique se o workflow deployer está **ativo** (toggle ON)
- Verifique a URL do webhook: `https://n8n.easyscale.co/webhook/gitops-deploy`
- No GitHub, vá em Settings → Webhooks → clique no webhook → aba **Recent Deliveries**

### Workflow não atualiza
- Verifique se `N8N_API_KEY` está configurada como variável de ambiente no n8n
- Teste a API manualmente: `curl -H "X-N8N-API-KEY: sua-chave" https://n8n.easyscale.co/api/v1/workflows`
- Verifique os logs de execução do workflow deployer no n8n

### Repo privado
Se o repositório for privado, os raw URLs do GitHub não serão acessíveis sem autenticação.
Nesse caso, troque o download para usar a API do GitHub com token.
