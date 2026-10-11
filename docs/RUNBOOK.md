# Runbook: uma rodada completa na nuvem

Passo a passo para subir o lab na sua assinatura Azure, publicar o app do `dx02v2`, destruir tudo e
registrar o resultado. Nada disto foi executado em nuvem na v2 (`não executado em nuvem (v2)`): você
será a primeira evidência. Os tempos abaixo são estimativas, não medições.

> **Custo**: com os padrões, cerca de US$0,51 por hora em `eastus2` (US$0,39 sem o WAF); o maior
> item é o Application Gateway for Containers com WAF (US$0,279/h). Preços de referência (Azure
> Retail Prices API, 2026-10-11) — confira a calculadora oficial e o `docs/CUSTOS.md`. Uma rodada de
> 3 horas fica perto de US$1,50; um lab esquecido passa de US$12 por dia. Destrua no mesmo dia.

## 1. Pré-requisitos

- Assinatura **dedicada** ao lab: o budget é da assinatura inteira e o `scripts/leftovers.sh` conta
  todo IP público, load balancer, disco, AGC e PostgreSQL dela.
- Você precisa ser **Owner** da assinatura para o bootstrap (registro de providers, grupos de
  recursos, atribuições de papel).
- **Free Trial** (o que o v1 encontrou em janeiro de 2026, `docs/LICOES_APRENDIDAS.md`, seção 1): o
  PostgreSQL Flexible Server foi bloqueado em todas as regiões testadas (`LocationIsOfferRestricted`);
  tamanhos de VM do AKS foram recusados por oferta e região; as cotas são baixas e assinaturas Free
  Trial não podem pedir aumento. O upgrade para pay-as-you-go remove as restrições da oferta e mantém
  o crédito restante até 30 dias depois do cadastro; a partir daí o budget importa ainda mais (ele só
  avisa, não bloqueia gastos).
- Cotas e tamanhos: `az vm list-skus --location eastus2 --size Standard_D2als_v6 --all --output table`
  (coluna Restrictions vazia) e `az vm list-usage --location eastus2 --output table` (4 vCPUs da
  família, 6 durante upgrades). A App Configuration Free aceita até 3 stores por região por
  assinatura.
- Ferramentas: Azure CLI (`az`), `gh` autenticado e as ferramentas do harness com `make tools`
  (terraform, kubectl, helm, kubelogin). O deploy do dx02v2 também precisa de Docker (veja o runbook
  dele).
- Repositórios `tx02v2` e `dx02v2` no GitHub (seus forks ou os originais), públicos e com
  `scripts/repo-guardrails.sh` aplicado (environment `lab` com revisor obrigatório e só `main`;
  `docs/PUBLICACAO.md`). As credenciais federadas aceitam só o environment `lab`.
- Tempo estimado: bootstrap ~5 min; apply ~30–45 min (AKS, PostgreSQL e AGC); plataforma ~10 min;
  deploy do dx02v2 ~15 min; destroy ~30–45 min. Uma rodada completa: 2–3 horas.

## 2. Bootstrap (uma vez, local, como Owner)

```bash
az login
az account set --subscription <SUBSCRIPTION_ID>
cd terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars   # subscription_id, budget_alert_emails, github_owner
terraform init
terraform apply
terraform output -raw backend_hcl > ../envs/lab/backend.hcl
terraform output github_variables_tx02v2       # seção 3
terraform output github_variables_dx02v2       # seção 3
```

O bootstrap registra os resource providers do lab, cria os grupos `tx02v2-bootstrap` e `tx02v2-lab`,
a conta de storage do state (`tx02v2tfstate<suffix>`, container `tfstate`, lock `CanNotDelete`), as
identidades `tx02v2-gha-plan`, `tx02v2-gha-apply` e `dx02v2-gha-deploy` com as credenciais federadas
e os papéis do contrato, e o budget mensal (padrão 25 na moeda de faturamento, alertas de 50, 80 e
100 % do valor real e de 100 % do previsto).

- O state do bootstrap fica **local** (`terraform.tfstate`, ignorado pelo git). Faça backup dele.
- O registro de providers pode levar alguns minutos no primeiro apply.
- **A armadilha do Owner**: Owner não tem *data actions*, e a conta do state não aceita chaves
  compartilhadas. Por isso o bootstrap dá `Storage Blob Data Contributor` no container a quem o
  aplica. A propagação do papel leva alguns minutos: se o `terraform init` do lab falhar logo em
  seguida com 403 (`AuthorizationPermissionMismatch`), espere e repita.
- Opcional, migrar o state do bootstrap para o container: crie `terraform/bootstrap/backend_override.tf`
  (ignorado pelo git) com o bloco abaixo e rode
  `terraform init -migrate-state -backend-config=../envs/lab/backend.hcl -backend-config="container_name=tfstate" -backend-config="key=bootstrap/terraform.tfstate"`.
  O harness lê todo `.tf` em `terraform/`: mantenha `use_azuread_auth = true` no arquivo. Antes do
  teardown (seção 10), volte para local: apague o arquivo e rode `terraform init -migrate-state`.

  ```hcl
  terraform {
    backend "azurerm" {
      use_azuread_auth = true
    }
  }
  ```

## 3. Variáveis do GitHub

Settings > Secrets and variables > Actions > **Variables**, como variáveis de repositório (o job de
plan não roda num environment). Elas aparecem nos logs: não coloque nada privado. Os workflows
conferem o formato no primeiro passo, mascaram nos logs os IDs de tenant, assinatura e client, o
object ID do deploy e o sufixo, e trocam todo GUID por `<GUID>` nos resumos.

### tx02v2

| Variável | Exemplo | Usada por | Vem de |
|---|---|---|---|
| `AZURE_TENANT_ID` | `00000000-0000-0000-0000-000000000000` | todos os workflows de nuvem | output `github_variables_tx02v2` |
| `AZURE_SUBSCRIPTION_ID` | `00000000-0000-0000-0000-000000000000` | todos os workflows de nuvem | idem |
| `AZURE_PLAN_CLIENT_ID` | `00000000-0000-0000-0000-000000000000` | plan (também liga a guarda do workflow) | idem (`plan_client_id`) |
| `AZURE_APPLY_CLIENT_ID` | `00000000-0000-0000-0000-000000000000` | apply, platform, destroy | idem (`apply_client_id`) |
| `TF_STATE_STORAGE_ACCOUNT` | `tx02v2tfstate00000000` | plan, apply, destroy | idem (`state_storage_account_name`) |
| `LAB_LOCATION` | `eastus2` | plan, apply, destroy (`TF_VAR_location`) | idem; tem de ser a região do bootstrap |
| `LAB_DEPLOY_PRINCIPAL_ID` | `00000000-0000-0000-0000-000000000000` | plan, apply, destroy (`TF_VAR_deploy_principal_id`) | idem (`deploy_principal_id`) |
| `LAB_CLUSTER_ADMIN_PRINCIPAL_IDS` | `["11111111-1111-1111-1111-111111111111","22222222-2222-2222-2222-222222222222"]` | `TF_VAR_cluster_admin_principal_ids` (lista JSON) | o output traz só o `apply_principal_id` (necessário para platform e destroy); acrescente o seu object ID (`az ad signed-in-user show --query id -o tsv`) |
| `LAB_API_SERVER_AUTHORIZED_IP_RANGES` | `["0.0.0.0/0"]` | `TF_VAR_api_server_authorized_ip_ranges` (lista JSON) | runners hospedados do GitHub têm IPs variáveis: precisam de `0.0.0.0/0` |
| `LAB_ALLOW_API_SERVER_FROM_ANYWHERE` | `true` | `TF_VAR_allow_api_server_from_anywhere` | opcional, padrão `false`; obrigatório com `0.0.0.0/0` |
| `LAB_APP_DEPLOYER_PRINCIPAL_IDS` | `[]` | `TF_VAR_app_deployer_principal_ids` e o workflow `platform` (RoleBinding) | opcional, padrão `[]`; object IDs de quem faz deploy do dx02v2 de um laptop |
| `LAB_ENABLE_WAF` | `true` | `TF_VAR_enable_waf` | opcional, padrão `true` (`docs/CUSTOS.md`) |

`TF_VAR_github_owner` vem de `github.repository_owner`. Os demais inputs usam os padrões de
`terraform/envs/lab/variables.tf`; para mudar um (por exemplo `node_vm_size`), adicione o
`TF_VAR_<nome>` ao bloco `env` dos workflows num PR. Com `0.0.0.0/0`, a API do AKS fica alcançável
de qualquer IP durante a rodada (o token do Entra ID e o RBAC continuam obrigatórios;
`docs/ARQUITETURA.md`, ADR 19).

### dx02v2

| Variável | Exemplo | Vem de |
|---|---|---|
| `AZURE_CLIENT_ID` | `00000000-0000-0000-0000-000000000000` | client ID de `dx02v2-gha-deploy` (output `github_variables_dx02v2`) |
| `AZURE_TENANT_ID` | `00000000-0000-0000-0000-000000000000` | idem |
| `AZURE_SUBSCRIPTION_ID` | `00000000-0000-0000-0000-000000000000` | idem |
| `AZURE_APPCONFIG_ENDPOINT` | `https://tx02v2-lab-00000000.azconfig.io` | idem; o store só existe depois do apply (output `appconfig_endpoint` do lab) |

O job `deploy-azure` do dx02v2 roda no environment `lab` daquele repositório (sujeito federado
`repo:<owner>/dx02v2:environment:lab`).

## 4. Apply

1. Dispare `terraform-plan` a partir de `main` (ou abra um PR que mexa em `terraform/**`) e leia o
   plano no resumo do job (GUIDs e sufixo substituídos).
2. Dispare `terraform-apply` e aprove o environment `lab`. O job planeja e aplica no mesmo run e
   escreve os outputs no resumo.

Alternativa local (suas credenciais). Owner não tem os papéis de dados que o apply usa
(`docs/ARQUITETURA.md`, "O dono da assinatura não lê dados"); dê-os a você no grupo do lab e remova
no teardown:

```bash
me="$(az ad signed-in-user show --query id -o tsv)"
for role in "Key Vault Secrets Officer" "App Configuration Data Owner"; do
  az role assignment create --assignee "$me" --role "$role" \
    --scope "/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/tx02v2-lab"
done
cd terraform/envs/lab
cp terraform.tfvars.example terraform.tfvars   # seus valores reais (arquivo ignorado pelo git)
export ARM_SUBSCRIPTION_ID=<SUBSCRIPTION_ID>
terraform init -backend-config=backend.hcl
terraform plan -out tfplan && terraform apply tfplan
terraform output
```

## 5. Plataforma

Dispare `platform` com `action=install` e aprove o environment `lab`. Ele precisa de
`tx02v2-gha-apply` em `LAB_CLUSTER_ADMIN_PRINCIPAL_IDS` e de um range que inclua os runners. O
`platform/install.sh`:

1. lê as chaves do contrato na App Configuration e os client IDs de `tx02v2-lab-alb` e
   `tx02v2-lab-eso`, e renderiza `platform/manifests` antes de instalar qualquer coisa;
2. gera um kubeconfig temporário (`az aks get-credentials` + `kubelogin convert-kubeconfig -l azurecli`);
3. baixa o chart do ALB Controller 1.12.2, recusa o arquivo se o SHA256 diferir de
   `platform/versions.env`, instala-o em `azure-alb-system` e confere os digests das imagens que os
   nós baixaram;
4. espera a GatewayClass `azure-alb-external` ficar `Accepted`;
5. instala o External Secrets Operator 2.12.0 com as anotações do Workload ID;
6. aplica namespace, Role, RoleBinding e ClusterSecretStore e espera o `azure-key-vault` ficar `Ready`
   (o ESO alcançou o Key Vault).

Localmente (seu object ID em `cluster_admin_principal_ids`, seu IP nos ranges e um papel de leitura na
App Configuration, como o Data Owner da seção 4):

```bash
make tools
az login && az account set --subscription <SUBSCRIPTION_ID>
APP_DEPLOYER_PRINCIPAL_IDS='[]' platform/install.sh   # a mesma lista de LAB_APP_DEPLOYER_PRINCIPAL_IDS
az aks get-credentials --resource-group tx02v2-lab --name tx02v2-lab --file /tmp/tx02v2-lab.kubeconfig
kubelogin convert-kubeconfig -l azurecli --kubeconfig /tmp/tx02v2-lab.kubeconfig
export KUBECONFIG=/tmp/tx02v2-lab.kubeconfig
kubectl get gatewayclass azure-alb-external
kubectl get clustersecretstore azure-key-vault
kubectl -n dx02v2 get role,rolebinding
```

`APP_DEPLOYER_PRINCIPAL_IDS` tem de ser a mesma lista da variável Terraform
`app_deployer_principal_ids`: o Terraform dá os papéis Azure, a plataforma dá a RoleBinding.

## 6. Deploy do app (dx02v2)

Siga o runbook do dx02v2: com as variáveis da seção 3, o workflow `deploy-azure` lê as 15 chaves
`tx02v2/lab/*`, publica `dx02v2/api` e `dx02v2/web` no ACR (tag = SHA do commit, nunca sobrescrita),
cria o ConfigMap `azure-pg-ca`, aplica o overlay `azure-waf` (ou `azure`, quando `waf/policy-id` é
`none`) no namespace `dx02v2` e roda o smoke test pelo Application Gateway for Containers.

Para fazer o deploy de um laptop, coloque o seu object ID em `LAB_APP_DEPLOYER_PRINCIPAL_IDS`, rode o
apply (papéis Azure de `dx02v2-gha-deploy` para você) e o `platform` de novo (RoleBinding).

## 7. Smoke test

```bash
terraform -chdir=terraform/envs/lab output -raw agc_frontend_fqdn
kubectl -n dx02v2 get gateway dx02v2                      # PROGRAMMED True, ADDRESS = FQDN do frontend
curl -fsS "http://<FQDN_DO_FRONTEND>/healthz"              # web
curl -fsS "http://<FQDN_DO_FRONTEND>/api/info"             # api
kubectl -n dx02v2 get externalsecrets                      # SecretSynced
kubectl -n dx02v2 get webapplicationfirewallpolicy         # com WAF: Accepted
```

Esperado, não verificado: com o WAF em Prevention, uma requisição com padrão de SQL injection recebe
403 do AGC (`curl -s -o /dev/null -w '%{http_code}\n' "http://<FQDN_DO_FRONTEND>/api/info?id=1%27%20OR%20%271%27=%271"`).
Registre o resultado no `cloud_run_report`.

## 8. Destroy

Dispare `terraform-destroy` com a confirmação `destroy tx02v2-lab` e aprove o environment `lab`. O job
roda `platform/uninstall.sh` (se o cluster existir: apaga HTTPRoutes, Gateways, políticas do ALB e
Services `LoadBalancer` e desinstala os releases), `terraform destroy`, faz login de novo e roda
`scripts/leftovers.sh --retry-for 900`. Qualquer erro para o job: leia o log, corrija e rode de novo.
Localmente:

```bash
platform/uninstall.sh
terraform -chdir=terraform/envs/lab destroy        # como Owner: -var purge_key_vault_on_destroy=true
scripts/leftovers.sh --retry-for 900
```

O grupo `tx02v2-lab` continua existindo, vazio (é do bootstrap); o grupo de nós `tx02v2-lab-nodes`
some com o cluster. O Key Vault fica em soft delete por 7 dias e prende o nome
(`docs/ARQUITETURA.md`, "A armadilha do soft delete").

## 9. Sobras

No workflow, o `scripts/leftovers.sh` roda com a identidade do apply, que só enxerga o que pode ler:
as listagens no escopo da assinatura podem voltar só os recursos de `tx02v2-lab`, sem erro, e o que
ela não pode ler de jeito nenhum (por exemplo o grupo de nós) aparece como `UNCHECKED`, com um aviso,
sem mudar o código de saída. Para uma checagem completa, rode localmente como Owner da assinatura:

```bash
az login && az account set --subscription <SUBSCRIPTION_ID>
scripts/leftovers.sh --retry-for 900
```

Níveis: `BILLABLE` (ainda custa; sai com 1), `ORPHANED` (grátis, mas atrapalha a próxima rodada),
`INFO` (recursos do bootstrap, nomes presos por soft delete), `UNCHECKED`; saída 2 = problema de
login ou erro da API. Remoção manual dos casos mais comuns:

```bash
az resource delete --ids <RESOURCE_ID>
az group delete --name tx02v2-lab-nodes --yes
az network public-ip delete --ids <RESOURCE_ID>
az network lb delete --ids <RESOURCE_ID>
az disk delete --ids <RESOURCE_ID> --yes
az keyvault purge --name tx02v2-lab-<suffix>
az monitor log-analytics workspace delete --resource-group tx02v2-lab --workspace-name tx02v2-lab-logs --force --yes
```

Rode o script de novo até não sobrar nada `BILLABLE`.

## 10. Teardown do bootstrap (fim da série de rodadas)

1. Lab destruído e `scripts/leftovers.sh` limpo, rodado localmente como Owner.
2. State do bootstrap de volta para local, se tiver sido migrado (seção 2).
3. Remova os papéis que você criou à mão (seção 4 e, se usou, o `Reader` do ALB Controller):
   `az role assignment delete --assignee <OBJECT_ID> --role "<papel>" --scope <escopo>`.
4. Em `terraform/bootstrap`: `state_protection_lock = false` no `terraform.tfvars`, `terraform apply`
   (só remove o lock) e `terraform destroy`. Isso apaga a conta do state com todas as versões, as três
   identidades, o papel personalizado do plan, as atribuições de papel, o budget e os dois grupos (o
   `tx02v2-lab` precisa estar vazio). Os registros de resource providers ficam (não custam nada).
5. Purgue o Key Vault em soft delete, se ainda existir, ou espere os 7 dias.
6. Confira o Cost Management no dia seguinte.

## 11. Registro

Abra uma issue com o template **Cloud run report**: data, região, oferta da assinatura, commits do
tx02v2/dx02v2, versões, passos, duração, custo observado no Cost Management (agrupe por medidor e
diga se o `FreeTierInfrastructureCost` do AKS apareceu; `docs/CUSTOS.md`), problemas e a saída
(redigida) do `scripts/leftovers.sh`. A matriz de status do README só muda com essa evidência.

## 12. Problemas comuns

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| `terraform init` do lab com 403 `AuthorizationPermissionMismatch` | papel de dados no container ausente ou ainda propagando | espere alguns minutos; confira o `Storage Blob Data Contributor` do bootstrap |
| `MissingSubscriptionRegistration` | bootstrap não aplicado nesta assinatura | aplique o bootstrap (seção 2) |
| `LocationIsOfferRestricted` | restrição da oferta Free Trial | upgrade para pay-as-you-go ou outra região (e `location` igual no bootstrap e no lab) |
| 403 ao gravar segredos ou chaves num apply local | Owner sem papéis de dados | seção 4 |
| Conflito de nome no Key Vault ao recriar o lab | vault da rodada anterior em soft delete | `az keyvault purge` como Owner ou espere 7 dias |
| `the API server of tx02v2-lab is not reachable from here` | IP fora de `api_server_authorized_ip_ranges`, ou identidade fora de `cluster_admin_principal_ids` | ajuste a variável e rode o apply |
| `AADSTS700024: Client assertion is not within its valid time range` | a asserção OIDC do GitHub expirou antes de o `az` obter tokens | rode o workflow de novo |
| HTTP 429 da App Configuration | tier Free: 1.000 requisições por dia | espere até a meia-noite UTC |
| Erro de autorização do ALB Controller no grupo de nós | `Reader` no grupo de nós não atribuído (desvio documentado) | `docs/ARQUITETURA.md`, "Desvio documentado" |
| `leftovers.sh` sai com 2 | `az` sem login ou erro da API | `az login` e rode de novo; nunca leia isso como "nada sobrou" |
