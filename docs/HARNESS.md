# Harness do tx02v2

O harness é o conjunto de checks que prova o que este repositório afirma, sem conta na nuvem.
Ele vive em `scripts/harness.sh`; o `Makefile` e o CI só o chamam, e o CI usa `HARNESS_STRICT=1`.
Duas diferenças conhecidas entre uma pasta sem commits e o CI: o `gitleaks` lê a árvore de trabalho
(no CI, o histórico inteiro) e o bit executável só é exigido de scripts que já estão no índice do git. `scripts/harness.sh list` mostra os checks: 35 no estágio `static`
e os 3 `terraform-test:*` no `test`, que também roda `tool-versions` (38 no `make verify`, que conta
o `tool-versions` uma vez), mais o `local-lab-e2e` no estágio `e2e` (`make e2e`, fora do `verify`).

## Camadas

| Camada | Check | O que prova | O que NÃO prova | Onde roda |
|---|---|---|---|---|
| Ferramentas | `make tools` | binários nas versões de `tools/versions.env`, SHA256 conferido (linux_amd64, linux_arm64, darwin_arm64) | — | local, CI |
| Versões | `tool-versions` | o PATH usa as versões fixadas (no modo estrito, divergência é FAIL) | — | local, CI |
| Estrutura e honestidade | `repo-structure`, `version-consistency` | arquivos obrigatórios; rótulos de status, sem auto-elogios, emojis ou links para o v1 nos READMEs; README com até 250 linhas; `CLAUDE.md`; LF; bit executável no índice do git (só um aviso para scripts ainda fora do índice); devcontainer por digest; versões coerentes entre arquivos | que a documentação está certa | local, CI |
| Políticas do Terraform | `policy-terraform`, `policy-tags` | erros do v1 não voltam (segredos write-only, PostgreSQL privado, só Entra ID, sem providers `kubernetes`/`helm`/`azuread`, sem Owner/User Access Administrator, nada no escopo da assinatura, sem `timestamp()` com diff perpétuo); tags do contrato em todo tipo de recurso que aceita `tags` no schema do provider fixado | intenção de quem escreveu | local, CI |
| Identificadores | `policy-identifiers` | sem GUIDs, IPs, e-mails ou IDs de 12 dígitos reais; os IDs de `modules/role-ids` são os IDs built-in verificados, nome por nome | identificadores fora desses formatos | local, CI |
| Workflows | `policy-workflows`, `actionlint` | actions por SHA, `permissions`, regras de OIDC, guardas, `-lock=false` só no plan, confirmação digitada e checagem de sobras no destroy; YAML, expressões e shellcheck dos blocos `run` | comportamento contra a Azure | local, CI |
| Scripts | `policy-scripts` | nenhuma variável de ambiente escolhe o alvo (`RESOURCE_GROUP`, `CLUSTER_NAME`, `LAB_*`); kubeconfig temporário (`--file "$KUBECONFIG"`) e kubelogin só nesse arquivo; `require_lab_cluster` (tag `Project=tx02v2`) em `platform/install.sh` e `platform/uninstall.sh`; `require_lab_context` nos scripts de `platform/local` | comportamento contra a Azure | local, CI |
| Exceções | `trivyignore-policy` | cada ignore tem `statement` e `expired_at` em até ~7 meses | — | local, CI |
| Contrato | `contract-platform`, `contract-appconfig` | os manifests renderizados são os do contrato (objetos, labels, regras da Role, sujeitos da RoleBinding, ClusterSecretStore); o renderizador recusa entradas inválidas; values e pins da plataforma; as 15 chaves de `contract.tf` = lista do harness, e cada uma tem uma linha na tabela de `docs/CONTRATO.md` | linhas a mais na tabela; o que o dx02v2 faz (o harness dele confere) | local, CI |
| Formato e sintaxe | `terraform-fmt`, `terraform-validate:*` (3 roots, 8 módulos) | HCL formatado e válido para o schema do provider fixado | que a Azure aceita os valores | local, CI |
| Lock de providers | `terraform-lockfiles` | pelo menos 4 hashes `h1:` por provider nos lock files dos roots (gerados para linux_amd64, linux_arm64, darwin_arm64, windows_amd64) | a qual plataforma cada hash pertence | local, CI |
| Lint | `tflint` | preset recommended + ruleset azurerm 0.32.0 sem issues | regras que dependem de chamadas à Azure | local, CI |
| Segurança da IaC | `trivy-config`, `trivy-config-tfvars` | sem HIGH/CRITICAL fora das exceções documentadas | configuração em runtime, RBAC efetivo | local, CI |
| Scripts | `shellcheck` | bash correto (nível style) em `scripts/` e `platform/` | comportamento contra a Azure | local, CI |
| Manifests | `kubeconform` | manifests renderizados válidos (estrito) para Kubernetes 1.36 e para os CRDs do ESO | admission e comportamento no cluster | local, CI (rede) |
| Charts da plataforma | `helm-template` | o chart do ALB Controller 1.12.2 tem o SHA256 registrado; os charts do ALB Controller, do ESO 2.12.0 e do OpenTelemetry Collector 0.176.0 aceitam `platform/values` e renderizam imagens, ServiceAccounts, anotações e labels do Workload ID, flags e o exporter do Azure Monitor com autenticação Entra ID; o Collector da nuvem usa o mesmo digest do lab local | instalação real e comportamento dos controllers | local, CI (rede) |
| Segredos | `gitleaks` | nenhum segredo conhecido (histórico completo quando há commits; antes disso, a árvore de trabalho) | segredos fora dos padrões do gitleaks | local, CI |
| Testes unitários | `terraform-test:bootstrap` (18 casos), `terraform-test:envs/lab` (57 casos) | sujeitos OIDC, state, papéis do plan e do apply, lista ABAC = papéis do lab, papéis dos deployers, budget, AKS, nós, PostgreSQL sem senha no state, Key Vault, ACR, AGC/WAF, chaves do contrato, Application Insights só com Entra ID, validações negativas | que os recursos sobem na Azure (provider mockado) | local, CI |
| Lab local: Terraform | `terraform-validate:envs/local`, `terraform-test:envs/local` (10 casos, só plan) | rede privada, labels em tudo, só o registry publicado e só em 127.0.0.1, banco só TLS, imagens por digest, validações negativas | que o Docker cria os contêineres (isso é o `e2e`) | local, CI |
| Lab local: plataforma | `local-versions`, `helm-template-local`, `kubeconform-local`, `policy-gator` | os 17 charts fixados por SHA256 renderizam só imagens por digest e Services ClusterIP; manifests válidos; cada política do Gatekeeper aceita e recusa os casos de `platform/local/policies/tests`; kind no mesmo minor do AKS do lab; gator igual ao Gatekeeper | comportamento no cluster | local, CI (rede) |
| Lab local: ponta a ponta | `local-lab-e2e` (`make e2e`) | apply do `terraform/envs/local`, instalação do perfil `full` e as 34 sondas de `platform/local/check.sh` (`docs/LAB_LOCAL.md`); destroy e checagem de sobras sempre | Azure | local (Docker, 8 GB), CI; `verificado no CI`; localmente em 2026-10-13 (`full`, 26 sondas de então) e 2026-10-14 (`observability`) |
| Nuvem | workflows `terraform-*`, `platform` | — | — | `não executado em nuvem (v2)` |

## Jobs do CI

| Job (`ci.yml`) | Alvo | Estágio do harness |
|---|---|---|
| `static` | `make tools && make static` | `static` |
| `test` | `make tools && make test` | `test` |
| `e2e` | `make tools && make e2e` | `e2e` (o lab local; diagnósticos como artifact em caso de falha) |

Os ids `static`, `test` e `e2e` são estáveis: são os checks exigidos pelo ruleset
(`.github/rulesets/main.json`; o `e2e`, o lab local, entrou em 2026-10-13); o `policy-workflows` falha se
um deles sumir. O CI não
recebe credenciais da Azure.

## Modo estrito

`HARNESS_STRICT=1` (definido no CI e no devcontainer) transforma todo `SKIP` em `FAIL` e exige que as
versões no PATH sejam as de `tools/versions.env`. Sem ele, um check só pode dar `SKIP` quando falta um
pré-requisito local (por exemplo, ferramenta não instalada) e sempre imprime o motivo.

Outras variáveis: `HARNESS_VERBOSE=1` mostra a saída dos checks que passam; `HARNESS_ONLY=<regex>`
roda só os checks cujo nome casa com a expressão (depuração local, por exemplo
`HARNESS_ONLY='^tflint$' scripts/harness.sh static`; o CI nunca usa); `HARNESS_WORK_DIR` muda a pasta
de dados (seção "Dados fora do repositório").

## Como adicionar um check

1. Escreva uma função `check_<nome>` em `scripts/harness.sh` que retorna 0 (PASS) ou não-zero (FAIL);
   use `need <ferramenta>` ou `skip "<motivo>"` só para pré-requisitos ausentes.
2. Registre-a em `register_checks` no estágio certo (`static` ou `test`).
3. Rode `scripts/harness.sh list` e `HARNESS_STRICT=1 make verify`. Prove que o check falha: aplique a
   mudança que ele deve pegar numa cópia do repositório e confira o `FAIL`.
4. Atualize esta tabela, `docs/GUARDRAILS.md` (se for um guardrail) e o CHANGELOG.

Ferramenta nova: adicione-a a `scripts/lib/tools.sh` (URLs oficiais), a `tools/versions.env` e rode
`scripts/update-tool-checksums.sh <ferramenta> <versão>`.

## Windows e macOS

- Windows: use o devcontainer (`.devcontainer/devcontainer.json`, imagem fixada por digest) ou WSL 2
  com Ubuntu. Git Bash não é suportado (as ferramentas são binários Linux/macOS).
- macOS (Apple Silicon): `brew install bash` (o bash 3.2 do sistema não serve; o harness exige
  bash >= 4.4) ou o devcontainer. Plataformas suportadas pelo `install-tools.sh`: linux_amd64,
  linux_arm64, darwin_arm64.
- Container avulso (como a verificação local deste repositório):
  `docker run --rm -e HARNESS_STRICT=1 -v "$PWD:/work" -w /work ubuntu:24.04 bash -c "apt-get update -qq && apt-get install -y -qq --no-install-recommends ca-certificates curl unzip git xz-utils make >/dev/null && make tools && make verify"`
  (adicione `-e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0=*` se o
  dono dos arquivos for outro usuário).

## Dados fora do repositório

O harness grava dados do Terraform (`TF_DATA_DIR`), o schema do provider, logs e caches em
`HARNESS_WORK_DIR` (padrão `$TMPDIR/tx02v2-harness`) e usa o cache de plugins `TF_PLUGIN_CACHE_DIR`
(padrão `~/.terraform.d/plugin-cache`, também cacheado no CI). No repositório ficam só `.tools/` e os
lock files dos módulos (ignorados pelo git). `make clean` remove `.tools/`, `.cache/`, os diretórios
`.terraform`, os lock files dos módulos e o `HARNESS_WORK_DIR` padrão; o cache de plugins e um
`HARNESS_WORK_DIR` personalizado ficam.

## Problemas comuns

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| `SKIP tool-versions (...) - missing tools: ...` | `make tools` não rodou | `make tools` |
| `FAIL terraform-validate:envs/lab` com erro de lock | provider mudou sem atualizar o lock | `terraform providers lock -platform=linux_amd64 -platform=linux_arm64 -platform=darwin_arm64 -platform=windows_amd64` no root (`docs/SUSTENTACAO.md`, 5.3) |
| `FAIL policy-tags ... has no tags` | recurso novo (ou tipo que passou a aceitar tags) sem `tags` | `tags = local.tags` no root, `tags = var.tags` no módulo |
| `FAIL contract-appconfig` | chave do contrato só em um dos três lugares | mude `contract.tf`, `CONTRACT_KEYS` e `docs/CONTRATO.md` juntos (e o dx02v2) |
| `FAIL helm-template ... SHA256` | o arquivo do chart no registry mudou | pare: não troque o SHA256 sem revisar o release (`docs/SUSTENTACAO.md`, 5.5) |
| `FAIL trivyignore-policy ... expired` | ignore venceu | revise a exceção: corrija o código ou renove com nova justificativa |
| `FAIL kubeconform ... could not find schema` | sem rede, ou schema do catálogo que o kubeconform não compila | confira a rede; veja a nota abaixo |
| `FAIL repo-structure ... not executable in the git index` | arquivo commitado do Windows sem o bit | `git update-index --chmod=+x <arquivo>` |
| `FAIL gitleaks` | segredo ou falso positivo | remova o segredo e gire a credencial; falso positivo vai para `.gitleaksignore` com justificativa no PR. Antes do primeiro commit o check roda `gitleaks dir .`, que também lê arquivos ignorados pelo git (`terraform.tfvars`, `backend.hcl`, `.env`): mantenha credenciais locais fora da pasta do repositório |
| `FAIL policy-identifiers` | GUID, e-mail ou IP real | use `00000000-0000-0000-0000-000000000000`, `you@example.com`, `203.0.113.10/32` |

Nota sobre o kubeconform (verificado em 2026-10-10 no tx01v2, mesmo pin aqui): a revisão de
2026-10-08 de `external-secrets.io/clustersecretstore_v1.json` no datreeio/CRDs-catalog (`b7e2015`,
gerada do ESO 2.12) contém `"additionalProperties": false` dentro de um mapa `properties` (provider
`crd`), e o kubeconform não consegue compilá-la ("could not find schema"). O harness usa a revisão
anterior (commit `f3e4382`, 2026-06-02), que valida o ClusterSecretStore deste repositório em modo
estrito (um campo com erro de digitação é rejeitado). Reavalie a cada revisão trimestral
(`docs/SUSTENTACAO.md`, 5.7).
