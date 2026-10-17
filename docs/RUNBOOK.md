# Runbook: uma rodada completa na nuvem

Passo a passo para subir o lab na sua assinatura Azure, publicar o app do `dx02v2`, destruir tudo e
registrar o resultado. Nada disto foi executado em nuvem na v2 (`não executado em nuvem (v2)`): você
será a primeira evidência. Os tempos abaixo são estimativas, não medições.

> **Custo**: com os padrões, cerca de US$0,51 por hora em `eastus2` (US$0,39 sem o WAF); o maior
> item é o Application Gateway for Containers com WAF (US$0,279/h). Preços de referência (Azure
> Retail Prices API, 2026-10-11) — confira a calculadora oficial e o `docs/CUSTOS.md`. Uma rodada de
> 3 horas fica perto de US$1,50; um lab esquecido passa de US$12 por dia. Destrua no mesmo dia.
>
> Com `profile=full` e `LAB_NODE_VM_SIZE=Standard_D2as_v5`, a estimativa é US$0,524/h com WAF
> (US$0,400/h sem) ou cerca de US$1,57 (US$1,20 sem WAF) por 3 horas. O padrão `core` continua
> usando `Standard_D2als_v6`. O perfil full não foi executado em nuvem; veja `docs/CUSTOS.md` para
> requests, hipóteses e custos variáveis de armazenamento/telemetria.

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
cp terraform.tfvars.example terraform.tfvars   # subscription_id, budget_alert_emails, github_owner e os três IDs
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

- `github_owner` não tem padrão: use o seu usuário do GitHub, o dono dos repositórios `tx02v2` e
  `dx02v2` (ou dos seus forks). O placeholder do exemplo (`your-github-user`) e o e-mail
  `you@example.com` são recusados.
- As credenciais federadas aceitam o `sub` **imutável** do GitHub, que leva os IDs numéricos do dono e
  do repositório: `repo:<dono>@<id do dono>/tx02v2@<id do repositório>:environment:lab`. Todo repositório
  criado depois de 2026-07-15 (um fork novo também) já emite esse formato; o formato antigo, só com os
  nomes, não casa e seria herdado por quem registrasse de novo um nome apagado. Os IDs vêm de
  `gh api users/<dono> --jq .id`, `gh api repos/<dono>/tx02v2 --jq .id` e
  `gh api repos/<dono>/dx02v2 --jq .id` (`github_owner_id`, `tx02v2_repository_id` e
  `dx02v2_repository_id` do `terraform.tfvars`); o `scripts/repo-guardrails.sh` também os imprime.
- Um repositório criado **antes** de 2026-07-15 precisa aderir às claims de sujeito imutáveis
  (Settings > Actions > General > OpenID Connect) antes do primeiro apply. Confira com
  `gh api repos/<dono>/tx02v2/actions/oidc/customization/sub`: o `sub_claim_prefix` deve ter os `@<id>`.
  Um repositório renomeado ou transferido muda o `sub`: aplique o bootstrap de novo.
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

Os perfis pagos de HA/DR e o restore isolado estão em [CONTINUIDADE.md](CONTINUIDADE.md).
Nos workflows plan/apply/destroy, `LAB_POSTGRES_PROFILE` seleciona `core` (padrão), `ha` ou `dr`;
`LAB_POSTGRES_HA_SKU` seleciona o SKU General Purpose (`GP_Standard_D2ads_v5` por padrão).
`LAB_POSTGRES_BACKUP_RETENTION_DAYS` controla 7–35 dias; `LAB_POSTGRES_GEO_BACKUP` opta por
geo backup na criação; `LAB_POSTGRES_DELETE_LOCK` cria lock apenas quando o operador tem permissão
para locks. O Contributor do CI não recebe permissão adicional para isso.

No `dr`, `LAB_DR_LOCATION` é `centralus` para o primário `eastus2`. As faixas podem ser dadas por
`LAB_DR_VNET_CIDR`, `LAB_DR_AKS_NODES_SUBNET_CIDR`, `LAB_DR_AGC_SUBNET_CIDR`,
`LAB_DR_POSTGRES_SUBNET_CIDR`, `LAB_DR_POD_CIDR`, `LAB_DR_SERVICE_CIDR`, `LAB_DR_DNS_SERVICE_IP`.
Defaults: `10.21.0.0/16`, `10.21.0.0/22`, `10.21.4.0/24`, `10.21.5.0/24`, `10.245.0.0/16`,
`10.1.0.0/16`, `10.1.0.10`. O Terraform recusa sobreposição interna e entre os clusters.
Mantenha os mesmos inputs no destroy. A troca de política de geo backup pode recriar PostgreSQL;
revise o plano e os backups antes de mudar um servidor existente.

Settings > Secrets and variables > Actions, como variáveis de repositório (o job de plan não roda
num environment). As variáveis aparecem nos logs: não coloque nada privado nelas. As três listas que
nomeiam as **pessoas e o endereço** de quem opera o lab (`LAB_API_SERVER_AUTHORIZED_IP_RANGES`,
`LAB_CLUSTER_ADMIN_PRINCIPAL_IDS` e `LAB_APP_DEPLOYER_PRINCIPAL_IDS`) são **secrets**, na aba Secrets:
os logs, o resumo e os artefatos de um repositório público são públicos, e um secret é mascarado (os
workflows ainda mascaram cada elemento da lista). Os workflows conferem o formato no primeiro passo,
mascaram nos logs os IDs de tenant, assinatura e client, o object ID do deploy e o sufixo, e trocam
todo GUID por `<GUID>` e todo endereço por `<CIDR>` ou `<IP>` nos resumos.

O `FORK.md` (passo 7) grava os outputs `github_variables_tx02v2` e `github_variables_dx02v2` do
bootstrap com `gh variable set -f` e o output `github_secrets_tx02v2` com `gh secret set -f`; as
variáveis e os secrets `LAB_*` que você escolhe vêm da tabela abaixo.

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
| `LAB_CLUSTER_ADMIN_PRINCIPAL_IDS` (**secret**) | `["11111111-1111-1111-1111-111111111111","22222222-2222-2222-2222-222222222222"]` | `TF_VAR_cluster_admin_principal_ids` (lista JSON) | o output `github_secrets_tx02v2` traz só o `apply_principal_id` (necessário para platform e destroy); acrescente o seu object ID (`az ad signed-in-user show --query id -o tsv`) |
| `LAB_API_SERVER_AUTHORIZED_IP_RANGES` (**secret**) | `["0.0.0.0/0"]` | `TF_VAR_api_server_authorized_ip_ranges` (lista JSON) | runners hospedados do GitHub têm IPs variáveis: precisam de `0.0.0.0/0` |
| `LAB_ALLOW_API_SERVER_FROM_ANYWHERE` | `true` | `TF_VAR_allow_api_server_from_anywhere` | opcional, padrão `false`; obrigatório com `0.0.0.0/0` |
| `LAB_APP_DEPLOYER_PRINCIPAL_IDS` (**secret**) | `[]` | `TF_VAR_app_deployer_principal_ids` e o workflow `platform` (RoleBinding) | opcional, padrão `[]`; object IDs de quem faz deploy do dx02v2 de um laptop |
| `LAB_ENABLE_WAF` | `true` | `TF_VAR_enable_waf` | opcional, padrão `true` (`docs/CUSTOS.md`) |
| `LAB_DNS_ZONE_NAME` | `example.com` | `TF_VAR_dns_zone_name` | obrigatório com os dois valores seguintes no perfil full; Terraform cria a zona pública no grupo do lab |
| `LAB_APP_DOMAIN_NAME` | `lab.example.com` | `TF_VAR_app_domain_name` | subdomínio da zona acima; CNAME aponta ao frontend do AGC |
| `LAB_ACME_CONTACT_EMAIL` | `you@example.com` | `TF_VAR_acme_contact_email` | contato não secreto para avisos de renovação do Let's Encrypt |
| `LAB_NODE_VM_SIZE` | `Standard_D2as_v5` | `TF_VAR_node_vm_size` em plan/apply/destroy | opcional; padrão `Standard_D2als_v6`; use D2as_v5 para o perfil full |
| `LAB_NODE_COUNT` | `2` | `TF_VAR_node_count` em plan/apply/destroy | opcional; 1–3, padrão `2`; mantenha o mesmo valor até destroy |
| `LAB_SLACK_WEBHOOK_URL` (**secret**) | URL de incoming webhook do Slack | workflow `platform`, perfil full | opcional; guardado em Secret do cluster, nunca nos values versionados |

`TF_VAR_github_owner` vem de `github.repository_owner`. Os demais inputs usam os padrões de
`terraform/envs/lab/variables.tf`; `LAB_NODE_VM_SIZE` e `LAB_NODE_COUNT` são opcionais e já são
repassados por plan, apply e destroy. Use `Standard_D2as_v5` e `2` para o perfil full; os valores
originais continuam como padrão do perfil core. Com `0.0.0.0/0`, a API do AKS fica alcançável
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
`repo:<owner>@<id do dono>/dx02v2@<id do repositório>:environment:lab`).

## 4. Apply

1. Dispare `terraform-plan` a partir de `main` (ou abra um PR que mexa em `terraform/**`) e leia o
   plano no resumo do job (GUIDs e sufixo substituídos).
2. Dispare `terraform-apply` e aprove o environment `lab`. O job planeja e aplica no mesmo run e
   escreve os outputs no resumo.

Para o perfil full, configure as três variáveis de DNS da seção 3 antes do plan/apply. Depois do
apply, copie `dns_name_servers` para a delegação da zona no registrador do domínio e espere a
resolução pública de `LAB_APP_DOMAIN_NAME` apontar ao `agc_frontend_fqdn` via CNAME. O Terraform
controla a zona e o registro, mas não compra o domínio nem altera a delegação no registrador. Sem
essa etapa, o desafio ACME do passo seguinte falha. O perfil core deixa as três variáveis vazias e
segue com HTTP de demonstração.

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

Dispare `platform` com `action=install`, escolha `profile=core` (padrão) ou `profile=full` e aprove o
environment `lab`. Para full, configure `LAB_NODE_VM_SIZE=Standard_D2as_v5` antes do plan/apply e
mantenha `LAB_NODE_COUNT=2`. O workflow precisa de `tx02v2-gha-apply` em
`LAB_CLUSTER_ADMIN_PRINCIPAL_IDS` e de um range que inclua os runners. O
`platform/install.sh`:

1. lê as chaves do contrato na App Configuration, os client IDs de `tx02v2-lab-alb`,
   `tx02v2-lab-eso` e `tx02v2-lab-otel` e a connection string de `tx02v2-lab-traces`, e renderiza
   `platform/manifests` antes de instalar qualquer coisa;
2. gera um kubeconfig temporário (`az aks get-credentials` + `kubelogin convert-kubeconfig -l azurecli`);
3. baixa o chart do ALB Controller 1.12.2, recusa o arquivo se o SHA256 diferir de
   `platform/versions.env`, instala-o em `azure-alb-system` e confere os digests das imagens que os
   nós baixaram;
4. espera a GatewayClass `azure-alb-external` ficar `Accepted`;
5. instala o External Secrets Operator 2.12.0 com as anotações do Workload ID;
6. aplica os namespaces `dx02v2` e `observability`, Role, RoleBinding e ClusterSecretStore;
7. instala o OpenTelemetry Collector (contrato v2) em `observability`, com o client ID de
   `tx02v2-lab-otel` e a connection string do Application Insights `tx02v2-lab-traces` num ConfigMap,
   e espera o `azure-key-vault` ficar `Ready` (o ESO alcançou o Key Vault).

No perfil `full`, o instalador exige DNS delegado, instala cert-manager e cria primeiro um Gateway
HTTP para o desafio ACME HTTP-01. Espera o certificado `dx02v2-tls` ficar Ready antes de instalar
as políticas de mTLS e antes do deploy do app. O cert-manager renova o Secret; o Gateway HTTPS do
dx02v2 o referencia. Na renovação, a rota HTTP-01 mais específica continua acessível na porta 80;
o `dx02v2` só admite tráfego da subnet do AGC ao solver na porta 8089. Esta emissão pública e a
renovação ainda não foram executadas em Azure.

O instalador acrescenta Istio ambient com waypoint, observabilidade no
cluster, Argo CD com GitOps, Gatekeeper, Kyverno, Trivy Operator, Velero Azure Blob e Chaos Mesh (16
charts fixados no total). O app-of-apps lê `platform/gitops` do tx02v2 na branch `main`; o Argo CD acompanha o repositório
público do dx02v2 na branch `gitops/azure` e sincroniza `deploy/k8s/overlays/azure`. O workflow
`deploy-azure` do dx02v2 publica essa branch e configura o overlay, as imagens e os IDs/CIDRs na
Application viva. A branch recebe apenas parâmetros de exemplo; IDs e CIDRs reais ficam no cluster.
Argo CD fica ClusterIP; use `kubectl port-forward` para acessar a UI. Kyverno exige que as imagens da
API e do web estejam referenciadas por digest e tenham uma atestação de promoção assinada pelo
workflow `deploy-azure.yml` do fork. Trivy e Kyverno acessam o ACR por Workload ID e têm leitura só nos
dois repositórios da aplicação. `platform/uninstall.sh` remove primeiro as Applications para impedir
que o Argo CD recrie rotas durante o teardown, depois remove as policies Kyverno e os PVCs de
monitoramento (discos `managed-csi` incluídos).

O Velero grava recursos Kubernetes no container Blob privado com a identidade federada do ServiceAccount
`velero/velero`; não faz snapshots nem cobre o PostgreSQL. Uma verificação de backup após uma rodada
aprovada pode usar `velero backup create dx02v2-smoke --include-namespaces dx02v2 --wait` e
`velero backup describe dx02v2-smoke --details`. Não remova o namespace do app para testar restore em
produção. Backup e restore ainda não foram executados em Azure.

#### Ensaio isolado de restore do Velero

Faça este drill somente numa rodada aprovada, com o perfil full instalado. Ele apaga apenas um
namespace temporário com um ConfigMap, não toca no `dx02v2` nem no banco. O backup fica no Blob até
ser apagado; confirme a saída dos comandos antes de continuar.

```bash
NAMESPACE=velero-restore-drill
BACKUP="velero-restore-drill-$(date -u +%Y%m%d%H%M%S)"
RESTORE="${BACKUP}-restore"

kubectl create namespace "$NAMESPACE"
kubectl create configmap restore-proof --namespace "$NAMESPACE" --from-literal=payload=restored
velero backup create "$BACKUP" --include-namespaces "$NAMESPACE" --wait
velero backup describe "$BACKUP" --details
kubectl delete namespace "$NAMESPACE" --wait
velero restore create "$RESTORE" --from-backup "$BACKUP" --wait
velero restore describe "$RESTORE" --details
kubectl get configmap restore-proof --namespace "$NAMESPACE" -o jsonpath='{.data.payload}'
# Confirme que o comando imprimiu "restored" e que o restore concluiu antes de limpar.
kubectl delete namespace "$NAMESPACE" --wait
velero restore delete "$RESTORE" --confirm
velero backup delete "$BACKUP" --confirm
```

Se backup ou restore não chegar a `Completed`, veja `velero backup logs "$BACKUP"` ou
`velero restore logs "$RESTORE"`, além do status do `BackupStorageLocation`. Corrija a identidade,
o container, a rede ou o RBAC antes de repetir. `velero backup delete` remove os dados do object
storage; apagar só o objeto Kubernetes com `kubectl delete backup` deixa o blob e a cobrança.

Ao atualizar um lab criado antes do contrato v3: `Monitoring Metrics Publisher` e
`Storage Blob Data Contributor` entraram na lista ABAC de `tx02v2-gha-apply`, então aplique o bootstrap
de novo (seção 2) antes do apply.

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

Siga o runbook do dx02v2: com as variáveis da seção 3, o workflow `deploy-azure` lê as 17 chaves
`tx02v2/lab/*`, publica `dx02v2/api` e `dx02v2/web` no ACR (tag = SHA do commit, nunca sobrescrita)
e cria o ConfigMap `azure-pg-ca`. Com o perfil `full`, `mode=gitops` (padrão) configura na Application
viva o overlay `azure-waf` (ou `azure`, quando `waf/policy-id` é `none`), as imagens e os parâmetros
reais; a branch pública recebe apenas exemplos. O workflow espera o Argo CD sincronizar, os
ExternalSecrets e os rollouts, depois roda o smoke test pelo Application Gateway for Containers.
Com o perfil `core` ou sem Argo CD, escolha `mode=push` para aplicar diretamente o overlay.

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

Traces (contrato v2), esperado e não verificado: depois de algumas requisições, o Application Insights
`tx02v2-lab-traces` mostra o serviço `dx02v2-api` (Transaction search ou o mapa da aplicação). Nada em
alguns minutos: `kubectl -n observability logs deployment/opentelemetry-collector` (erro 401/403 do
exporter `azure_monitor`: papel ou credencial federada de `tx02v2-lab-otel`).

Esperado, não verificado: com o WAF em Prevention, uma requisição com padrão de SQL injection recebe
403 do AGC (`curl -s -o /dev/null -w '%{http_code}\n' "http://<FQDN_DO_FRONTEND>/api/info?id=1%27%20OR%20%271%27=%271"`).
Registre o resultado no `cloud_run_report`.

## 8. Destroy

Dispare `terraform-destroy` com a confirmação `destroy tx02v2-lab` e aprove o environment `lab`. O job
roda `scripts/destroy.sh --subscription <ID>`:

1. `platform/uninstall.sh`, se o cluster existir (apaga HTTPRoutes, Gateways, políticas do ALB e
   Services `LoadBalancer` e desinstala os releases). Como apaga tudo isso no cluster que alcança, ele
   só age no cluster `tx02v2-lab` do grupo `tx02v2-lab` com a tag `Project=tx02v2`; nenhuma variável
   de ambiente (`RESOURCE_GROUP`, `CLUSTER_NAME`) muda o alvo, e o kubeconfig dele é temporário.
2. Se o passo 1 falhar (API do cluster fora do ar ou fora de `api_server_authorized_ip_ranges`,
   controlador parado, tempo esgotado), o destroy **segue**: neste lab o controlador não é dono de
   nenhum recurso da Azure (o AGC, o frontend e a associação são do Terraform; os IPs públicos dos
   Services ficam no grupo de nós, que o AKS apaga com o cluster). Um aviso `warning:
   platform/uninstall.sh did not finish` marca esse caminho.
3. `terraform destroy`.

Depois, o workflow faz login de novo e roda `scripts/leftovers.sh --subscription <ID> --retry-for 900`
com `if: always()`, também depois de um destroy que falhou. Qualquer erro aparece no log: leia,
corrija e rode de novo. O fluxo é testado sem Azure (check `destroy-flow` do harness, com `az`,
`terraform`, `kubectl`, `helm` e `kubelogin` simulados). Localmente:

```bash
export TF_STATE_STORAGE_ACCOUNT=<conta do state> ARM_SUBSCRIPTION_ID=<ID>   # mais as TF_VAR_* do lab
scripts/destroy.sh --subscription "$ARM_SUBSCRIPTION_ID"        # como Owner: TF_VAR_purge_key_vault_on_destroy=true
scripts/leftovers.sh --subscription "$ARM_SUBSCRIPTION_ID" --retry-for 900
```

**Rodada interrompida** (um apply ou destroy cancelado, ou que estourou o tempo) deixa o *lease* do
blob do state: o próximo `terraform` falha com `Error acquiring the state lock` e um `ID`. Rode
`terraform-destroy` com o input `force_unlock_id` preenchido com esse ID (localmente,
`scripts/destroy.sh --subscription <ID> --force-unlock <ID>`). Se o apply parou no meio e criou algo que
não entrou no state, o próximo apply falha com `already exists` ou `ResourceAlreadyExists`: importe o
recurso (`terraform import <endereço> <id>`) ou apague-o, e rode de novo.

O grupo `tx02v2-lab` continua existindo, vazio (é do bootstrap); o grupo de nós `tx02v2-lab-nodes`
some com o cluster. O Key Vault fica em soft delete por 7 dias e prende o nome
(`docs/ARQUITETURA.md`, "A armadilha do soft delete"). A purga pede uma permissão no escopo da
assinatura, que as identidades de CI não têm: o `scripts/leftovers.sh` imprime, como `INFO`, o comando
exato de cada vault e de cada App Configuration em soft delete do lab, para rodar como Owner:

```bash
az keyvault purge --name tx02v2-lab-<suffix> --location <location> --subscription <ID>
az appconfig purge --name tx02v2-lab-<suffix> --location <location> --subscription <ID> --yes
```

## 9. Sobras

O `scripts/leftovers.sh` recebe sempre a assinatura (`--subscription <ID>`): toda chamada `az` a
nomeia, e o `az account set` da máquina nunca decide o que é varrido. Só conta como sobra o que é do
lab: recurso com a tag `Project=tx02v2` ou nos grupos `tx02v2-lab` e `tx02v2-lab-nodes`. O mesmo tipo
de recurso de outro trabalho na assinatura (IP público, load balancer, disco, PostgreSQL, AGC) aparece
como `INFO` ("not the lab's"), **nunca** como algo a apagar. No workflow, o script roda com a identidade
do apply, que só enxerga o que pode ler: o que ela não pode ler de jeito nenhum (por exemplo o grupo
de nós) aparece como `UNCHECKED`, com um aviso, sem mudar o código de saída. Para uma checagem
completa, rode localmente como Owner da assinatura:

```bash
az login
scripts/leftovers.sh --subscription <SUBSCRIPTION_ID> --retry-for 900
```

Níveis: `BILLABLE` (ainda custa; sai com 1), `ORPHANED` (grátis, mas atrapalha a próxima rodada),
`INFO` (recursos do bootstrap, nomes presos por soft delete, itens de outro trabalho), `UNCHECKED`;
saída 2 = problema de login ou erro da API. Remoção manual dos casos mais comuns, **só para itens
`BILLABLE` ou `ORPHANED`** (confira a tag `Project=tx02v2` ou o prefixo `tx02v2-lab` antes):

```bash
az resource delete --ids <RESOURCE_ID>
az group delete --name tx02v2-lab-nodes --yes
az network public-ip delete --ids <RESOURCE_ID>
az network lb delete --ids <RESOURCE_ID>
az disk delete --ids <RESOURCE_ID> --yes
az keyvault purge --name tx02v2-lab-<suffix> --location <location>
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
