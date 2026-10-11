# Sustentação do tx02v2

Como manter o repositório saudável sem conta na nuvem: rotinas, calendário de fim de suporte e
procedimentos passo a passo. Datas e versões verificadas em 2026-10-11.

## 1. Objetivo e escopo

Cobre o código (Terraform, scripts, workflows), as ferramentas do harness, as versões de plataforma
(AKS, Azure Linux, PostgreSQL, ALB Controller, External Secrets) e as rodadas opcionais em nuvem. Não
cobre o app (ver `dx02v2`), mas lista o que precisa mudar junto com ele.

## 2. Estado atual

- Harness completo (`HARNESS_STRICT=1 make verify`, 32 checks) `verificado no CI` (jobs `static` e
  `test` verdes no GitHub) e também em container Linux local.
- Bootstrap, apply, plan em PRs, plataforma e destroy: `não executado em nuvem (v2)`.
- Contrato com o dx02v2: versão 1 (`docs/CONTRATO.md`).

## 3. Rotinas

| Quando | O quê | Como |
|---|---|---|
| Semanal (automático) | CI agendado (segunda 06:00 UTC) roda todo o harness | Falhou? Seção 6. Causas típicas: ignore vencido, URL ou chart que mudou, rede |
| Mensal | PRs do Dependabot (actions, providers Terraform, pre-commit) | Playbook "Dependency updater" do `AGENTS.md`; um PR por grupo, harness verde antes do merge |
| Trimestral | Ferramentas do harness, ALB Controller e ESO (charts e digests), versões de plataforma, schemas do kubeconform, preços do `docs/CUSTOS.md`, ignores perto de vencer, regras `ignore` do Dependabot | Seções 4 e 5; registre no CHANGELOG |
| Por rodada em nuvem: antes | Ler `docs/CUSTOS.md`, conferir o budget, CI verde no commit, variáveis do GitHub, cotas e restrições de tamanho | `docs/RUNBOOK.md`, seção 1 |
| Por rodada em nuvem: durante | Anotar horários e problemas; não deixar a rodada aberta de um dia para o outro | `docs/RUNBOOK.md` |
| Por rodada em nuvem: depois | destroy, `scripts/leftovers.sh` limpo localmente como Owner, issue `cloud_run_report`, matriz de status só com evidência | `docs/RUNBOOK.md`, seções 8 a 11 |

## 4. Calendário de fim de suporte

| Componente | Versão | Fim do suporte | Fonte | Ação |
|---|---|---|---|---|
| Kubernetes no AKS | 1.36 (padrão do lab; GA no AKS em 2026-06-30) | fim de vida 2027-06-30; "platform support" até o GA da 1.40; upgrade iniciado pela plataforma previsto para setembro de 2027 | [versões suportadas do AKS](https://learn.microsoft.com/azure/aks/supported-kubernetes-versions) | Migrar para a 1.37 antes de 2027-06-30 (5.4). `automatic_upgrade_channel = "patch"` só aplica patches da 1.36 |
| Kubernetes no AKS | 1.37 (GA no AKS em outubro de 2026) | fim de vida 2027-10-31 | idem | Candidata a padrão na próxima revisão trimestral, depois de conferir ALB Controller, ESO e schemas |
| Azure Linux (nós) | 3.0 (`os_sku = "AzureLinux"` no AKS 1.32 ou mais novo) | suportada no AKS até "cerca de três anos depois do lançamento da 1.32" (sem data exata); o Azure Linux 2.0 está sem suporte desde 2025-11-30 e suas imagens são removidas a partir de 2026-10-31 | [ciclo de vida do Azure Linux no AKS](https://learn.microsoft.com/azure/azure-linux/aks-support-cycle) | Acompanhar a data do 3.0 e a versão sucessora |
| PostgreSQL Flexible Server | 17 | suporte padrão da Azure até 2029-11-08 (data da comunidade); depois, Extended Support pago | [política de versões](https://learn.microsoft.com/azure/postgresql/configure-maintain/concepts-version-policy) | Upgrade de major (mudança de contrato, PR no dx02v2) antes de 2029-11-08 |
| Terraform CLI | 1.16.5 (`>= 1.11.0, < 2.0.0`) | sem data fixa | [releases](https://releases.hashicorp.com/terraform/) | Trimestral (5.2) |
| Provider hashicorp/azurerm | 5.9.0 (`~> 5.9`) | sem data fixa; uma major 6 exigirá migração (o Dependabot ignora majors) | registry.terraform.io | Dependabot mensal (5.3); a cada versão, reavaliar os papéis do plan (5.10) |
| Provider hashicorp/random | 3.9.1 (`~> 3.9`) | sem data fixa | registry.terraform.io | Dependabot mensal |
| ALB Controller (AGC) | 1.12.2 (Gateway API v1.5.1, Kubernetes mínimo 1.32) | sem política de fim de suporte publicada; o add-on do AKS usa 1.11.x no AKS 1.36+ | [release notes do ALB Controller](https://learn.microsoft.com/azure/application-gateway/for-containers/alb-controller-release-notes) | Trimestral (5.5), junto com o dx02v2 |
| External Secrets Operator | v2.12.0 (chart 2.12.0, CRDs `external-secrets.io/v1`) | o projeto mantém só as versões recentes | [releases](https://github.com/external-secrets/external-secrets/releases) | Trimestral (5.6), junto com o tx01v2 |
| kubelogin | 0.2.21 (2026-10-09) | sem política publicada | [releases](https://github.com/Azure/kubelogin/releases) | Trimestral (5.1) |
| kubectl / Helm | 1.37.1 / 4.3.0 | kubectl suporta ±1 minor da API (1.36–1.38) | kubernetes.io, helm.sh | Acompanhar a versão do cluster; o Helm 4 usa `--rollback-on-failure` no lugar de `--atomic` |
| Ingress no AKS (contexto) | — | ingress-nginx upstream aposentado em 2026-03-24; o add-on de app routing com NGINX do AKS tem suporte até novembro de 2026 | [AKS blog](https://blog.aks.azure.com/2025/11/13/ingress-nginx-update) | O lab usa AGC; não voltar ao ingress-nginx |
| `azure/login` | v3.1.0 | sem data publicada | [releases](https://github.com/Azure/login/releases) | Dependabot de actions (5.8) |
| Raízes de CA do PostgreSQL (contrato) | DigiCert Global Root G2; Microsoft RSA e ECC Root CA 2017 | 2038-01-15; 2042-07-18 | [Azure CA details](https://learn.microsoft.com/azure/security/fundamentals/azure-ca-details) | Trocar uma raiz é mudança de contrato |
| Runners e devcontainer | Ubuntu 24.04 LTS | suporte padrão até 2029-04 | ubuntu.com | Trocar antes do fim |
| Schema do ClusterSecretStore (kubeconform) | datreeio/CRDs-catalog `f3e4382` (2026-06-02) | — | `docs/HARNESS.md` | Reavaliar a cada revisão trimestral (5.7) |
| Exceções do trivy | 2 entradas (`AZU-0012`, `AZU-0013`) | 2027-04-30 | `.trivyignore.yaml` | Revisar até abril de 2027 (5.9) |

## 5. Procedimentos

### 5.1 Ferramenta do harness (terraform, tflint, ruleset azurerm, trivy, actionlint, shellcheck, kubeconform, gitleaks, kubectl, helm, kubelogin)

```bash
scripts/update-tool-checksums.sh trivy 0.76.0   # baixa o arquivo de checksums oficial da release
make tools && HARNESS_STRICT=1 make verify
git diff tools/ .tflint.hcl                     # versions.env + checksums.txt (+ .tflint.hcl para o ruleset)
```

O script lê o arquivo de checksums publicado na release exata (o shellcheck não publica: o script
baixa os três artefatos e calcula o SHA256) para linux_amd64, linux_arm64 e darwin_arm64. Leia as
release notes antes. Casos especiais:

- gitleaks: atualize também o `rev:` do hook em `.pre-commit-config.yaml` (SHA do commit da tag +
  `# frozen: vX.Y.Z`); o `version-consistency` compara os dois.
- tflint-ruleset-azurerm: o script já atualiza o `version` de `.tflint.hcl`; confira que o ruleset
  carrega com o azurerm 5.x (`tflint` com 0 issues).
- trivy: achados novos aparecem com a ferramenta nova, porque o harness usa as regras embutidas
  (`--skip-check-update`).
- kubectl: fique a no máximo uma minor de distância do cluster.

### 5.2 Terraform CLI

Atualize com `scripts/update-tool-checksums.sh terraform <versão>`. `required_version` só muda se a
versão mínima precisar subir (todos os `versions.tf` iguais, checado pelo `version-consistency`).

### 5.3 Providers (azurerm, random) e lock em 4 plataformas

1. Leia o CHANGELOG e, numa major, o upgrade guide do provider (na v5: `resource_provider_registrations`,
   `rbac_authorization_enabled`, `node_provisioning_profile`, argumentos write-only).
2. Mesma restrição em todos os `versions.tf`, inclusive os de `terraform/modules/*` (o PR do
   Dependabot só altera os roots; o `version-consistency` exige a mesma restrição em todos).
3. Em `terraform/bootstrap` e `terraform/envs/lab`:
   ```bash
   terraform init -backend=false -upgrade
   terraform providers lock -platform=linux_amd64 -platform=linux_arm64 -platform=darwin_arm64 -platform=windows_amd64
   ```
4. `HARNESS_STRICT=1 make verify`: `terraform-lockfiles` exige 4 hashes `h1:` por provider, os dois
   roots precisam travar a mesma versão do azurerm e o `policy-tags` relê o schema do provider (um
   tipo de recurso que passou a aceitar tags precisa de `tags`).
5. Faça a revisão de papéis do plan da seção 5.10.

### 5.4 Versão do Kubernetes

Mudar `kubernetes_version` é mudança de contrato (versão + PR no dx02v2). Antes: release notes do
AKS, Kubernetes mínimo do ALB Controller e compatibilidade do ESO. Depois:

1. `kubernetes_version` em `terraform/envs/lab/variables.tf` (e o texto da descrição).
2. `K8S_SCHEMA_KUBERNETES_VERSION` em `scripts/harness.sh`, com um `K8S_SCHEMA_REF` que tenha essa
   versão (o `version-consistency` compara a minor padrão com a dos schemas).
3. `kubectl` a no máximo uma minor de distância (5.1).
4. No dx02v2: a mesma minor nos schemas, no kind e no kubectl dele (`docs/SUSTENTACAO.md` de lá).

### 5.5 ALB Controller (junto com o dx02v2)

1. Leia as [release notes](https://learn.microsoft.com/azure/application-gateway/for-containers/alb-controller-release-notes)
   (Gateway API, Kubernetes mínimo, mudanças de CRD) e o guia de upgrade com Helm.
2. Chart: `helm pull oci://mcr.microsoft.com/application-lb/charts/alb-controller --version <versão>`
   e `sha256sum alb-controller-<versão>.tgz` → `ALB_CONTROLLER_CHART_VERSION` e
   `ALB_CONTROLLER_CHART_SHA256` em `platform/versions.env`.
3. Imagens (o chart usa uma tag só para as três e não aceita digest): para `alb-controller`,
   `alb-controller-bootstrap` e `alb-controller-crds`,
   `docker buildx imagetools inspect mcr.microsoft.com/application-lb/images/<imagem>:<versão>` → o
   digest do índice em `*_IMAGE_SHA256` e o do manifest `linux/amd64` em `*_IMAGE_AMD64_SHA256`.
4. `albController.image.tag` em `platform/values/alb-controller.yaml` igual à versão do chart (o
   `version-consistency` confere).
5. `HARNESS_STRICT=1 make verify`: o `helm-template` baixa o chart, confere o SHA256 e renderiza com
   os values; o `contract-platform` confere os values e os pins.
6. No dx02v2, `scripts/update-crd-schemas.sh <versão>` regenera os schemas a partir da imagem de CRDs.
   Confira ali os `spec.names.plural` de `healthcheckpolicy` e `webapplicationfirewallpolicy`: se
   mudarem, a Role do contrato muda (versão + PRs nos dois repositórios).
7. Releia a documentação do modo "bring your own" (papéis da identidade, nome da credencial federada,
   ServiceAccount `alb-controller-sa`) e atualize o `docs/ARQUITETURA.md` se algo mudar.

O `platform/install.sh` recusa um chart com outro SHA256 e pods com digests que não estejam em
`platform/versions.env`.

### 5.6 External Secrets Operator (junto com o tx01v2)

`ESO_CHART_VERSION` em `platform/versions.env` e o digest da imagem nas três entradas de
`platform/values/external-secrets.yaml` (controller, webhook e cert controller usam a mesma imagem;
o `version-consistency` exige `v<versão>@sha256:` três vezes). Use a mesma release e o mesmo digest
do tx01v2. Se a versão de API dos CRDs mudar (`external-secrets.io/v1` hoje), é mudança de contrato.

### 5.7 Schemas do kubeconform

`K8S_SCHEMA_REF` (yannh/kubernetes-json-schema) e `CRD_SCHEMA_REF` (datreeio/CRDs-catalog) em
`scripts/harness.sh` apontam para commits fixos, os mesmos do tx01v2:
`gh api 'repos/datreeio/CRDs-catalog/commits?path=external-secrets.io/clustersecretstore_v1.json&per_page=3'`.
Veja a nota sobre o schema do ESO em `docs/HARNESS.md`.

### 5.8 Digests de imagens e actions

Devcontainer: `docker buildx imagetools inspect mcr.microsoft.com/devcontainers/base:ubuntu-24.04`.
Actions (fora do Dependabot): `gh api repos/<o>/<r>/git/ref/tags/<tag>`; se `object.type == "tag"`,
siga `gh api repos/<o>/<r>/git/tags/<sha>`; use o SHA do commit com `# vX.Y.Z` e confirme que ele
existe (`gh api repos/<o>/<r>/commits/<sha>`; o v1 fixou SHAs inexistentes). O
`version-consistency` exige um SHA por action em todos os workflows.

### 5.9 Revisão das exceções do trivy

Para cada entrada de `.trivyignore.yaml` perto do `expired_at`: o motivo ainda vale? Se sim, renove
por até ~7 meses com a justificativa atualizada; se não, corrija o código e remova a entrada. O
`trivyignore-policy` recusa entradas vencidas ou com validade longa demais.

### 5.10 Papéis do plan depois de um bump do azurerm

O plan só funciona se o refresh do provider não pedir nada além dos papéis de `tx02v2-gha-plan`
(`docs/ARQUITETURA.md`, ADR 14). Numa versão nova do azurerm, procure no código do provider o que o
`Read` de `azurerm_kubernetes_cluster`, `azurerm_key_vault`, `azurerm_key_vault_secret`,
`azurerm_app_configuration` e `azurerm_app_configuration_key` chama. Se aparecer uma chamada nova,
ajuste `plan_roles` em `terraform/bootstrap/roles.tf` com o papel de menor privilégio e o teste
`plan_identity_is_read_only`.

### 5.11 Preços

Na revisão trimestral, refaça as consultas da Azure Retail Prices API
(`https://prices.azure.com/api/retail/prices?$filter=...`) para cada linha do `docs/CUSTOS.md`,
atualize a data e os totais do README e confira o medidor `FreeTierInfrastructureCost` do AKS.

## 6. Resposta a problemas

| Situação | Primeiros passos |
|---|---|
| CI vermelho | Leia o primeiro `FAIL` (o log do check vem logo abaixo). Corrija no código; nunca enfraqueça o check. Reproduza com `HARNESS_STRICT=1 make verify` |
| Vulnerabilidade | Alerta do Dependabot ou advisory: atualize por PR. Em ferramenta do harness: 5.1. Em chart ou imagem da plataforma: 5.5/5.6. Reporte privado: `SECURITY.md` |
| Alerta de custo (e-mail do budget) | `scripts/leftovers.sh` localmente como Owner; se houver lab de pé, rode o destroy; confira o Cost Management por medidor |
| Credencial exposta | Não há segredos de longa duração no GitHub; se um segredo do Key Vault vazar, gire com `db_password_version`/`admin_token_version` e rode o apply. Revise atribuições de papel e credenciais federadas das identidades no portal. Reescrever histórico é decisão do mantenedor |
| Sobras após o destroy | Siga a saída de `scripts/leftovers.sh` e a seção 9 do `docs/RUNBOOK.md`; registre no `cloud_run_report` |
| Nome preso por soft delete | `docs/ARQUITETURA.md`, "A armadilha do soft delete" |

## 7. Registro de execuções em nuvem

Toda rodada gera uma issue com o template `cloud_run_report` (data, região, oferta, commits, passos,
duração, custo observado, problemas, sobras). A matriz de status do README só muda com essa evidência.

## 8. Responsáveis

Mantenedor: @maringelix (decisões, merges, rodadas em nuvem). Agentes de IA seguem o `AGENTS.md`.
