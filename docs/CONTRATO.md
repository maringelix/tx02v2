# Contrato tx02v2 <-> dx02v2 — versão 3 (2026-10-16)

Versão 3: labels ambient e Gatekeeper no namespace do app, GitOps com Argo CD no perfil full e backup
Azure Blob com Workload ID. As 15 chaves da App Configuration não mudam. A versão 2 adicionou traces
pelo OpenTelemetry Collector.

Interface entre a infraestrutura (este repositório) e a aplicação (`dx02v2`). Esta é a fonte da
verdade: `dx02v2/docs/CONTRATO.md` repete a parte que o app usa e aponta para cá. Qualquer mudança
exige PRs coordenados nos dois repositórios e incremento da versão. Os dois harnesses conferem a
parte que cada um controla. O formato é o mesmo do contrato AWS (`tx01v2` ⇄ `dx01v2`), com os
serviços equivalentes da Azure.

## Como o contrato é verificado aqui

| O quê | Onde | Status |
|---|---|---|
| Identidades do GitHub: nomes, issuer, audience e um sujeito exato por credencial federada | `terraform/bootstrap/tests/identities.tftest.hcl` | `verificado localmente` |
| Papéis do plan e do apply; a condição ABAC do apply lista exatamente os papéis que o root do lab atribui | `terraform/bootstrap/tests/roles.tftest.hcl`, `terraform/envs/lab/tests/roles.tftest.hcl` | `verificado localmente` |
| Papéis de `dx02v2-gha-deploy`, dos `app_deployer_principal_ids`, do ESO, do ALB Controller, do OpenTelemetry Collector e do kubelet | `terraform/envs/lab/tests/roles.tftest.hcl` | `verificado localmente` |
| Velero: identidade federada, Blob privado, firewall `Deny` com acesso só pela subnet AKS, lifecycle de 35 dias e role de dados no container | `terraform/envs/lab/tests/roles.tftest.hcl`, `terraform/envs/lab/tests/network.tftest.hcl`, `helm-template-full` | `verificado localmente` |
| GitOps: app-of-apps do Argo CD, branch `gitops/azure` e RoleBinding restrita do deployer | `contract-platform`, `helm-template-full` | `verificado localmente` |
| Application Insights dos traces só com ingestão por Entra ID (autenticação local desligada), workspace e limites diários | `terraform/envs/lab/tests/roles.tftest.hcl` (`traces_accept_only_entra_id_ingestion`) | `verificado localmente` |
| Collector no namespace `observability`, exporter do Azure Monitor com Entra ID, mesmo digest do lab local | checks `contract-platform` e `helm-template` | `verificado localmente` |
| As 15 chaves da App Configuration (prefixo, valores fixos, origem de cada valor) | `terraform/envs/lab/tests/lab.tftest.hcl`; o check `contract-appconfig` confere que `contract.tf` e a lista do harness são iguais e que cada chave tem uma linha na tabela deste arquivo | `verificado localmente` |
| Key Vault, segredos write-only, PostgreSQL, ACR | `terraform/envs/lab/tests/data_stores.tftest.hcl` | `verificado localmente` |
| AGC, frontend, política de WAF (Prevention, DRS 2.1, Bot Manager 1.1, 128 KB) e `none` sem WAF | `terraform/envs/lab/tests/agc.tftest.hcl` | `verificado localmente` |
| Subnet do AGC exatamente /24, CIDRs sem sobreposição | `terraform/envs/lab/tests/validations.tftest.hcl`, `network.tftest.hcl` | `verificado localmente` |
| Namespace, Role, RoleBinding e ClusterSecretStore renderizados | checks `contract-platform` e `kubeconform` | `verificado localmente` |
| Comportamento real na Azure | `docs/RUNBOOK.md` | `não executado em nuvem (v2)` |

## Equivalência com o contrato AWS

| AWS (tx01v2) | Azure (tx02v2) |
|---|---|
| EKS + access entries | AKS + Entra ID (Azure RBAC para admins, Kubernetes RBAC para o deployer) |
| EKS Pod Identity | Microsoft Entra Workload ID (identidades user-assigned + credenciais federadas) |
| RDS PostgreSQL 17 | Azure Database for PostgreSQL Flexible Server 17 (acesso privado) |
| Secrets Manager | Key Vault (autorização RBAC) |
| SSM Parameter Store | App Configuration (tier Free) |
| ECR | Azure Container Registry (Basic) |
| ALB (Load Balancer Controller) + WAF | Application Gateway for Containers (ALB Controller, Gateway API) + política de WAF (DRS 2.1) |
| Papéis IAM com OIDC do GitHub | managed identities user-assigned com credenciais federadas do GitHub |
| AWS Budgets | budget do Cost Management (escopo da assinatura) |

## Identificadores

| Item | Valor |
|---|---|
| Região Azure | variável Terraform `location`, padrão `eastus2` |
| Projeto / ambiente / prefixo | `tx02v2` / `lab` / `tx02v2-lab` |
| Tags (todo recurso que aceita tags; o azurerm não tem tags padrão no provider) | `Project=tx02v2`, `Environment=lab`, `ManagedBy=terraform`, `Repository=<owner>/tx02v2` |
| Grupos de recursos | `tx02v2-bootstrap` (state, identidades de CI; do bootstrap), `tx02v2-lab` (recursos do lab; **criado pelo bootstrap**, preenchido pelo root do lab), grupo de nós do AKS `tx02v2-lab-nodes` |
| Sufixo dos nomes globais | `suffix = substr(sha1(<subscription_id>), 0, 8)` (determinístico, sem random) |
| Cluster AKS | `tx02v2-lab`, Kubernetes `1.36`, contas locais desligadas, Entra ID com Azure RBAC, OIDC issuer + workload identity, Azure CNI Overlay com dataplane Cilium (aplica NetworkPolicy) |
| Nós | x86-64 (padrão `Standard_D2als_v6`): as imagens do dx02v2 são `linux/amd64`, então `node_vm_size` não pode ser um tamanho Arm64 (nada no código impede; é regra do contrato) |
| Namespace do app | `dx02v2` — criado pela plataforma com Pod Security `restricted`, Istio ambient (`istio.io/dataplane-mode=ambient`) e enforcement Gatekeeper (`policy.lab/enforce=true` no perfil full) |
| NetworkPolicy do app com Istio ambient | O dataplane Cilium aplica as políticas; permitir HBONE em TCP 15008 entre pods na malha e as sondas do kubelet em `169.254.7.127/32` (ver `docs/ARQUITETURA.md`, ADR 41); o harness do `dx02v2` confere as regras |
| Traces (OpenTelemetry, versão 2) | `http://opentelemetry-collector.observability.svc:4318` (OTLP/HTTP). O Collector é instalado pela camada de plataforma no namespace `observability` (mesmos labels de Pod Security) e grava os spans no Application Insights `tx02v2-lab-traces` (workspace `tx02v2-lab-traces`, autenticação local desligada) com a identidade `tx02v2-lab-otel` (Workload ID, sujeito `system:serviceaccount:observability:opentelemetry-collector`; só `Monitoring Metrics Publisher` nesse Application Insights). O app não recebe nenhum papel Azure para isso |
| RBAC Kubernetes do deployer | Role `dx02v2-deployer` + RoleBinding `dx02v2-deployers` no namespace `dx02v2`; sujeito `kind: User`, `name: <object ID da identidade dx02v2-gha-deploy>` (mais os object IDs de `app_deployer_principal_ids`) |
| ACR | nome `tx02v2lab<suffix>`, Basic, usuário admin e pull anônimo desligados; repositórios `dx02v2/api`, `dx02v2/web`; imagens com a tag do SHA git completo (40 caracteres) do dx02v2. O Basic não tem imutabilidade de tags no repositório inteiro: o deploy recusa sobrescrever uma tag existente. A identidade kubelet do AKS tem `AcrPull` no registry |
| Identidades OIDC do GitHub (user-assigned, em `tx02v2-bootstrap`) | `tx02v2-gha-plan`, `tx02v2-gha-apply`, `dx02v2-gha-deploy` |

Regras da Role `dx02v2-deployer` (namespace `dx02v2`), as mesmas do contrato AWS v1, com os CRDs de
tráfego da Azure no lugar do Ingress:

- `apps`: deployments → get, list, watch, create, update, patch, delete; replicasets → get, list, watch
- core: services, configmaps, serviceaccounts → get, list, watch, create, update, patch, delete;
  pods, pods/log, events, endpoints → get, list, watch; secrets → get, list, watch (o ESO escreve
  os segredos; o deployer nunca os escreve)
- `networking.k8s.io`: networkpolicies → CRUD completo (mesmos verbos de deployments)
- `gateway.networking.k8s.io`: gateways, httproutes → CRUD completo
- `alb.networking.azure.io`: `healthcheckpolicy`, `webapplicationfirewallpolicy` → CRUD completo. São
  os valores exatos de `spec.names.plural` dos CRDs do ALB Controller 1.12.2 (parecem singulares de
  propósito; `healthcheckpolicies`/`webapplicationfirewallpolicies` não casam com nada). O RBAC usa
  esses nomes.
- `autoscaling`: horizontalpodautoscalers → CRUD completo; `policy`: poddisruptionbudgets → CRUD completo
- `external-secrets.io`: externalsecrets → CRUD completo

## OIDC do GitHub

Credenciais federadas com issuer `https://token.actions.githubusercontent.com`, audience
`api://AzureADTokenExchange`, dono configurável (`github_owner`, sem padrão: o dono do repositório ou do seu fork) e uma
credencial por sujeito exato.

| Identidade | Sujeitos |
|---|---|
| `tx02v2-gha-plan` | `repo:<owner>@<owner id>/tx02v2@<repo id>:pull_request`, `repo:<owner>@<owner id>/tx02v2@<repo id>:ref:refs/heads/main` |
| `tx02v2-gha-apply` | `repo:<owner>@<owner id>/tx02v2@<repo id>:environment:lab` |
| `dx02v2-gha-deploy` | `repo:<owner>@<owner id>/dx02v2@<repo id>:environment:lab` |

O sujeito é o **imutável** do GitHub (repositórios criados depois de 2026-07-15 ou que aderiram): leva o
ID numérico do dono e o do repositório (`github_owner_id`, `tx02v2_repository_id`,
`dx02v2_repository_id`), então um nome de conta apagado e registrado de novo não herda o lab. O
environment `lab` só implanta a partir de `main`. A identidade `tx02v2-gha-plan` só tem `Reader` no
`tx02v2-lab` e a leitura do state: nenhum plano de dados (nenhum valor de segredo, nenhuma chave da App
Configuration, nenhuma credencial do AKS), e por isso o plan roda com `-refresh=false`.

Papéis Azure de `dx02v2-gha-deploy` (atribuídos pelo root do lab): `AcrPush` no registry;
`Azure Kubernetes Service Cluster User Role` no cluster (para obter o kubeconfig);
`App Configuration Data Reader` no store do contrato. Nada no Key Vault. Acesso Kubernetes só pela
RoleBinding acima.

Os `app_deployer_principal_ids` (pessoas que fazem o deploy do dx02v2 a partir de um laptop) recebem
os mesmos três papéis Azure, nos mesmos escopos, além de entrarem como sujeitos da RoleBinding.
Também não recebem nada no Key Vault.

## Store do contrato: App Configuration `tx02v2-lab-<suffix>`

Tier Free, autenticação local desligada, chaves sem label, prefixo `tx02v2/lab/`. O endpoint do store
é um output do tx02v2 (`appconfig_endpoint`) e vira a variável `AZURE_APPCONFIG_ENDPOINT` do GitHub
no dx02v2. Nenhum valor é segredo.

| Chave | Valor |
|---|---|
| `location` | região Azure |
| `resource-group` | `tx02v2-lab` |
| `cluster-name` | `tx02v2-lab` |
| `vnet-cidr` | CIDR da VNet |
| `agc-subnet-cidr` | subnet delegada ao Application Gateway for Containers, exatamente um /24 (o tráfego AGC → pods sai dela) |
| `postgres-subnet-cidr` | subnet delegada ao PostgreSQL Flexible Server |
| `acr/login-server` | `<nome do acr>.azurecr.io` |
| `keyvault/uri` | URI do Key Vault |
| `db/secret-name` | `tx02v2-lab-db-app` |
| `app/admin-token-secret-name` | `tx02v2-lab-app-admin-token` |
| `eso/cluster-secret-store` | `azure-key-vault` |
| `agc/id` | resource ID do Application Gateway for Containers |
| `agc/frontend-name` | nome do frontend do AGC |
| `waf/policy-id` | resource ID da política de WAF, ou o literal `none` quando o tx02v2 roda com `enable_waf = false` |
| `deploy/principal-id` | object ID de `dx02v2-gha-deploy` |

## Key Vault `tx02v2-lab-<suffix>`

Autorização RBAC; os valores são gravados com argumentos write-only e nunca entram no state nem no
plan.

- `tx02v2-lab-db-app`: JSON com valores string `username`, `password`, `host`, `port`, `dbname`.
  `host` é o FQDN do servidor (`<nome>.postgres.database.azure.com`), o nome que o `verify-full`
  confere.
- `tx02v2-lab-app-admin-token`: string pura, 48 caracteres alfanuméricos aleatórios.
- A identidade do ESO `tx02v2-lab-eso` (federada com
  `system:serviceaccount:external-secrets:external-secrets`) tem `Key Vault Secrets User` só neste
  vault.

## Camada de plataforma (instalada pelo `platform/install.sh` do tx02v2, nunca pelo Terraform)

- ALB Controller 1.12.2 (Application Gateway for Containers) no namespace `azure-alb-system`,
  identidade `tx02v2-lab-alb` federada com o ServiceAccount `alb-controller-sa` do controller, com os
  papéis do modo "bring your own" (`docs/ARQUITETURA.md`); GatewayClass `azure-alb-external`.
- External Secrets Operator 2.12.0 no namespace `external-secrets`, ServiceAccount `external-secrets`
  (anotação `azure.workload.identity/client-id`, label de pod `azure.workload.identity/use: "true"`);
  ClusterSecretStore `azure-key-vault` (provider `azurekv`, `authType: WorkloadIdentity`, `vaultUrl`
  do contrato, `serviceAccountRef` external-secrets/external-secrets), utilizável só a partir do
  namespace `dx02v2`.
- Namespace `dx02v2`, Role e RoleBinding acima.

### Perfil cloud full (R4)

O workflow `platform` aceita `profile=core` (padrão) ou `profile=full`. O perfil full instala os 15
charts de `platform/full/charts.txt`, todos fixados por versão, SHA256 do pacote e digests de imagem.
Inclui Istio ambient; cert-manager; Prometheus, Alertmanager, Grafana, Loki, Alloy, Tempo e Collector;
Argo CD; Gatekeeper; Trivy Operator; Velero; e Chaos Mesh. Os overlays Azure usam Azure Monitor e
Blob em vez de X-Ray e S3.

O app-of-apps do Argo CD acompanha `platform/gitops` no repositório público do tx02v2, branch `main`.
A Application `dx02v2` acompanha o repositório público do app, branch `gitops/azure`, overlay
`deploy/k8s/overlays/azure`, com sync automático, self-heal e prune. Argo CD não expõe LoadBalancer.
A identidade de deploy pode fazer `get`, `watch` e `patch` apenas na Application `dx02v2`; não lista nem
altera outras Applications.

O workflow atualiza na Application viva o overlay, as imagens e os IDs/CIDRs da implantação. A
Application `platform` ignora apenas `spec.source.path`, `spec.source.kustomize.images` e
`spec.source.kustomize.patches` da Application `dx02v2`, para o self-heal do pai preservar esses
valores. A branch pública `gitops/azure` recebe a revisão e parâmetros de exemplo; IDs e CIDRs reais
permanecem no cluster.

Velero usa o plugin Azure e Entra Workload ID para gravar recursos Kubernetes no container Blob
privado do lab. Não cria snapshots de disco nem substitui o backup gerenciado do PostgreSQL. A role
`Storage Blob Data Contributor` fica apenas no escopo do container; os blobs expiram após 35 dias.
A Storage Account mantém endpoint público porque o AKS não usa Private Endpoint, mas o firewall nega
por padrão e libera apenas a subnet dos nós AKS via service endpoint `Microsoft.Storage`. Não permite
acesso anônimo e desliga as chaves compartilhadas. Backup e restore em Azure ainda não foram
executados (`não executado em nuvem (v2)`).

## Runtime do app (dx02v2)

- Secret `db-credentials`: chaves `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD` (Azure:
  ExternalSecret de `tx02v2-lab-db-app`; local/kind/compose: gerado em tempo de execução).
- Secret `app-secrets`: chave `ADMIN_TOKEN` (Azure: ExternalSecret de `tx02v2-lab-app-admin-token`).
- TLS do banco na Azure: `DB_SSL_MODE=verify-full`, `DB_SSL_CA_FILE=/etc/azure-pg-ca/ca.pem` a partir
  do ConfigMap `azure-pg-ca`, criado pelo deploy. O bundle é a concatenação PEM de três raízes (o
  documento de TLS do Azure Database for PostgreSQL exige pelo menos as duas primeiras e recomenda
  todas as raízes da Azure; lista e thumbprints SHA-1 da página "Azure Certificate Authority
  details"). O deploy baixa cada uma em DER, converte para PEM e **recusa** um arquivo cujo
  thumbprint SHA-1 seja diferente. Os SHA-256 e as validades abaixo foram calculados dos downloads em
  2026-10-11 (iguais aos do dx02v2):

  | Raiz | URL (DER) | SHA-1 (contrato) | SHA-256 | Validade |
  |---|---|---|---|---|
  | DigiCert Global Root G2 | `https://cacerts.digicert.com/DigiCertGlobalRootG2.crt` | `DF3C24F9BFD666761B268073FE06D1CC8D4F82A4` | `CB3CCBB76031E5E0138F8DD39A23F9DE47FFC35E43C1144CEA27D46A5AB1CB5F` | 2038-01-15 |
  | Microsoft RSA Root Certificate Authority 2017 | `https://www.microsoft.com/pkiops/certs/Microsoft%20RSA%20Root%20Certificate%20Authority%202017.crt` | `73A5E64A3BFF8316FF0EDCCC618A906E4EAE4D74` | `C741F70F4B2A8D88BF2E71C14122EF53EF10EBA0CFA5E64CFA20F418853073E0` | 2042-07-18 |
  | Microsoft ECC Root Certificate Authority 2017 | `https://www.microsoft.com/pkiops/certs/Microsoft%20ECC%20Root%20Certificate%20Authority%202017.crt` | `999A64C37FF47D9FAB95F14769891460EEC4C3C5` | `358DF39D764AF9E1B766E9C972DF352EE15CFAC227AF6AD1D70E8E4A6EDCBA02` | 2042-07-18 |

  Local: `DB_SSL_MODE=disable`.
- Services: `api` (porta 3000 http, 9464 métricas), `web` (porta 8080).
- Tráfego (só Azure): Gateway `dx02v2` (classe `azure-alb-external`, anotação
  `alb.networking.azure.io/alb-id` = `agc/id`, e uma entrada em `spec.addresses` do tipo
  `alb.networking.azure.io/alb-frontend` com o valor `agc/frontend-name` — a forma "bring your own"
  da documentação do AGC), listener HTTP na porta 80 (HTTPS `planejado`); HTTPRoute: `/api` →
  `api:3000`, `/` → `web:8080`; HealthCheckPolicy: web `/healthz`, api `/readyz`;
  WebApplicationFirewallPolicy apontando para o Gateway com `waf/policy-id` (omitida quando é `none`).
- A subnet do AGC (`agc-subnet-cidr`) é exatamente um /24: o Application Gateway for Containers com
  Azure CNI Overlay exige isso (os dois repositórios conferem).
- Política de WAF (do tx02v2): modo Prevention, regras gerenciadas DRS 2.1 + Bot Manager 1.1, inspeção
  do corpo ligada com limite de 128 KB — então corpos maiores que o limite da API e menores que 128 KB
  (o smoke do dx02v2 manda 70 KB) chegam à API, que responde 413 ela mesma (o WAF da AWS responde 403
  acima de 8 KB). Nenhuma regra personalizada pode bloquear o smoke test; se uma regra de limite de
  taxa for adicionada, o limite precisa ser >= 300 requisições por minuto por cliente.
- NetworkPolicies na Azure: entrada em web:8080 e api:3000 só a partir de `agc-subnet-cidr`; saída
  da api para `postgres-subnet-cidr`:5432; DNS.
- PostgreSQL Flexible Server 17, porta 5432, só acesso privado (subnet delegada + zona DNS privada),
  `require_secure_transport = on`, TLS >= 1.2.

## Respostas às notas de implementação do dx02v2 (2026-10-11)

O `docs/CONTRATO.md` do dx02v2 registrou quatro notas pendentes de decisão aqui. Todas estão
resolvidas no texto acima, sem mudar a versão (nenhum valor mudou):

1. Frontend do AGC: `spec.addresses` com o tipo `alb.networking.azure.io/alb-frontend` e a anotação
   `alb.networking.azure.io/alb-id` no Gateway (forma "bring your own").
2. Nomes dos recursos para RBAC: `healthcheckpolicy` e `webapplicationfirewallpolicy`, exatamente
   como os CRDs do ALB Controller 1.12.2 declaram (check `contract-platform`).
3. Corpo do smoke: 70 KB, abaixo dos 128 KB do WAF; a conclusão (413 da própria API) não muda.
4. Lacunas: `host` é o FQDN do servidor; o kubelet tem `AcrPull`; os nós são x86-64; a subnet do AGC
   é exatamente /24 (validação de `agc_subnet_cidr`); os `app_deployer_principal_ids` recebem os
   papéis Azure de `dx02v2-gha-deploy` (teste `app_deployers_get_the_roles_of_the_deploy_identity`).

## Lab local (contrato local, versão 2)

O lab local (`docs/LAB_LOCAL.md`) é um contrato à parte, com versão própria (chave `version`), lido
pelo deploy local do dx02v2. Ele espelha o contrato da nuvem com nomes do lab local; não muda nada
acima. As chaves são as mesmas do lab local do `tx01v2` (o app consome os dois do mesmo jeito).
Publicado por `platform/local/install.sh` no ConfigMap `lab-system/lab-contract`:

| Chave | Valor | Equivale na nuvem |
|---|---|---|
| `version` | `2` (2026-10-14: `tracing.otlp-endpoint`; a versão 1 não tinha traces) | versão deste arquivo |
| `cluster-name` | `tx02v2-local` | `cluster-name` |
| `network-cidr` | `10.251.0.0/24` (ou `subnet_cidr`) | `vnet-cidr` |
| `registry` | `registry.tx02v2.local` (nome das imagens no cluster) | `acr/login-server` (prefixo) |
| `registry-push` | `localhost:5002` (push desta máquina) | — |
| `db.endpoint-ip`, `db.hostname`, `db.port` | `10.251.0.11`, `db.tx02v2.local`, `5432` | FQDN do PostgreSQL Flexible Server (`host` de `tx02v2-lab-db-app`) |
| `db.secret-name` | `tx02v2-lab-db-app` (chaves `host`, `port`, `dbname`, `username`, `password`) | `db/secret-name` |
| `db.ca-configmap` | `lab-system/lab-ca` (chave `ca.crt`) | bundle `azure-pg-ca` (três raízes, criado pelo deploy) |
| `app.admin-token-secret-name` | `tx02v2-lab-app-admin-token` (chave `token`; no Key Vault é uma string pura) | `app/admin-token-secret-name` |
| `eso.cluster-secret-store` | `local-secrets` (só o namespace `dx02v2`) | `eso/cluster-secret-store` |
| `gateway.class` | `istio` (Gateway API) | GatewayClass `azure-alb-external` (com `agc/id` e `agc/frontend-name`) |
| `tls.cluster-issuer` | `lab-ca` (cert-manager) | — (HTTPS no listener do AGC `planejado`) |
| `gitops.push-url`, `gitops.read-url` | `ssh://10.251.0.13:23231/dx02v2-gitops`, `http://10.251.0.13:23232/dx02v2-gitops.git` | — |
| `gitops.push-key-secret` | `lab-secrets/gitops-push-key` (chave SSH do push, `kubernetes.io/ssh-auth`) | identidade `dx02v2-gha-deploy` |
| `argocd.project` | `dx02v2` (AppProject: só o repositório GitOps, só o namespace `dx02v2`, só os kinds do deploy, nada de Secret ou recurso de cluster) | Role `dx02v2-deployer` |
| `monitoring.prometheus-service-account` | `monitoring/kube-prometheus-stack-prometheus` (identidade do Prometheus no mesh) | — |
| `tracing.otlp-endpoint` | `http://opentelemetry-collector.monitoring.svc:4318` (OTLP/HTTP do OpenTelemetry Collector; o app manda os spans por ele, pelo mesh, e os Gateways mandam os deles em OTLP/gRPC na porta 4317) | `http://opentelemetry-collector.observability.svc:4318` |

Os Secrets `tx02v2-lab-db-app` e `tx02v2-lab-app-admin-token` ficam no namespace `lab-secrets` (o
gêmeo local do Key Vault) com os mesmos nomes dos segredos do Key Vault, que já são válidos no
Kubernetes. Regras do namespace `dx02v2` no lab local: Pod Security `restricted`, mesh ambient
(`istio.io/dataplane-mode: ambient`), constraints do Gatekeeper em `deny` (`policy.lab/enforce:
"true"`; imagens só de `registry.tx02v2.local/`), métricas do app coletadas pelo Prometheus do
namespace `monitoring`. O deploy local escreve no repositório GitOps; quem aplica no cluster é o Argo
CD. Diferença de borda: o Gateway local mantém um `X-Request-Id` externo; o AGC gera o próprio.

## Mudando o contrato

1. Abra PRs nos dois repositórios, com links cruzados, e incremente a versão no título dos dois
   arquivos `docs/CONTRATO.md`.
2. Atualize os testes e checks que cobrem o item (tabela "Como o contrato é verificado aqui"); uma
   chave nova da App Configuration muda `terraform/envs/lab/contract.tf`, `CONTRACT_KEYS` em
   `scripts/harness.sh` e a tabela acima, juntos.
3. Faça o merge do lado que publica (tx02v2) antes do lado que consome (dx02v2), salvo remoções (ao
   contrário).
