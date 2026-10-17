# Guardrails do tx02v2

Um guardrail é uma regra mais o mecanismo que a faz valer — automático sempre que possível. Este
documento lista as regras do repositório, onde cada uma é aplicada e o que elas não garantem.
Tipos: `bloqueante` (falha o harness/CI ou o apply), `alerta` (notifica), `processo` (disciplina
humana/agente). Os testes citados ficam em `terraform/*/tests/` e rodam com `make test`.

## Regras

| ID | Regra | Por quê | Onde é aplicada | Tipo |
|---|---|---|---|---|
| SEC-01 | Nenhum segredo no repositório | repositório público; histórico é para sempre | `gitleaks` (harness, pre-commit) | bloqueante |
| SEC-02 | Sem identificadores reais: GUIDs só placeholders de um dígito repetido (`00000000-...`) ou IDs de papéis built-in nomeados; e-mails `example.com`; IPs privados ou RFC 5737 | evita expor assinaturas, tenants e pessoas | check `policy-identifiers` | bloqueante |
| SEC-03 | Segredos gerados por recursos `ephemeral` e gravados só com argumentos write-only (`administrator_password_wo`, `value_wo`); nenhum `random_password`/`random_string` como recurso | o valor nunca entra no plan nem no state | `policy-terraform`; testes `postgres_password_never_in_plan_or_state`, `key_vault_and_secrets` | bloqueante |
| SEC-04 | GitHub → Azure só por credenciais federadas com sujeito exato (o imutável, com os IDs numéricos do dono e do repositório), issuer do GitHub e audience `api://AzureADTokenExchange`; o apply só com `environment:lab`; o deploy só do dx02v2 com `environment:lab` | sem segredos; nenhum outro repo, branch ou environment obtém as identidades; um nome de conta apagado e registrado de novo não herda o lab | `identities.tftest.hcl` (`identities_follow_the_contract`); `scripts/repo-guardrails.sh` confere o sujeito do repositório | bloqueante |
| SEC-05 | `id-token: write` só em jobs de nuvem com `environment: lab` (o plan, atrás da guarda); nunca no `ci.yml`; sem `client-secret`, `creds` ou chaves de storage em workflows | limita quem obtém credenciais | `policy-workflows` | bloqueante |
| SEC-06 | API server público restrito a `api_server_authorized_ip_ranges`; `0.0.0.0/0` exige `allow_api_server_from_anywhere = true` | reduz exposição; a escolha fica explícita | validação + `validations.tftest.hcl`; `aks.tftest.hcl` | bloqueante |
| SEC-07 | Identidades de CI com papéis só em `tx02v2-lab` ou no container do state; nada no escopo da assinatura; Owner e User Access Administrator nunca atribuídos | o lab não alcança o resto da assinatura | `bootstrap/tests/roles.tftest.hcl`; `policy-terraform` | bloqueante |
| SEC-08 | O apply só atribui os 11 papéis built-in de `modules/role-ids` (condição ABAC), e o root do lab atribui exatamente os papéis necessários; ACR usa condições por repositório | o apply não consegue se promover; kubelet, Trivy e Kyverno só leem os dois repositórios do app, deployers só escrevem neles e Velero só acessa seu container Blob | testes `apply_identity_is_scoped_to_the_lab`, `the_lab_assigns_exactly_the_abac_roles`, `no_app_deployers_assign_nothing_extra` | bloqueante |
| SEC-09 | Só Entra ID: contas locais do AKS desligadas + Azure RBAC; ACR sem admin e sem pull anônimo; App Configuration sem autenticação local; storage sem chaves compartilhadas; Key Vault com autorização RBAC | nenhuma credencial estática existe | `policy-terraform`; testes do AKS e de `data_stores` | bloqueante |
| SEC-10 | PostgreSQL só privado (sem acesso público, sem regras de firewall), TLS obrigatório (>= 1.2) e 5432 liberado só da subnet dos nós | o banco não tem porta na Internet | `policy-terraform`; testes `postgres_server`, `postgres_is_reachable_only_from_the_aks_nodes` | bloqueante |
| SEC-11 | Deployers não recebem nada no Key Vault; o ESO só tem `Key Vault Secrets User` no vault do lab | menor privilégio sobre segredos | `the_lab_assigns_exactly_the_abac_roles` | bloqueante |
| SEC-12 | Plan só para PRs do próprio repositório (guarda `head.repo.full_name == github.repository`) e só com `AZURE_PLAN_CLIENT_ID` configurada | forks nunca recebem credenciais | `terraform-plan.yml`; `policy-workflows` | bloqueante |
| SEC-13 | O bootstrap não tem dono padrão: `github_owner` é obrigatório e o placeholder `your-github-user` é recusado; `budget_alert_emails` recusa o placeholder `you@example.com` | um fork que esquecesse de trocar o dono confiaria nos repositórios de outra pessoa, e sem um e-mail lido o alerta de custo não chega (`FORK.md`) | validações das variáveis; `placeholder_owner_is_refused`, `placeholder_alert_email_is_refused` | bloqueante |
| SEC-15 | As listas que nomeiam quem opera o lab (`LAB_API_SERVER_AUTHORIZED_IP_RANGES`, `LAB_CLUSTER_ADMIN_PRINCIPAL_IDS`, `LAB_APP_DEPLOYER_PRINCIPAL_IDS`) são secrets, e cada workflow de nuvem mascara cada elemento; o resumo do job e os artefatos trocam GUIDs, CIDRs e IPs | os logs, o resumo e os artefatos de um repositório público são públicos (o IP de casa de quem faz fork, o object ID dele) | `policy-workflows` | bloqueante |
| SEC-14 | Scripts só agem no que o lab criou: o alvo vem do contrato (`tx02v2-lab`) e é conferido pela tag `Project=tx02v2` antes de qualquer mudança (nenhuma variável de ambiente, como `RESOURCE_GROUP` ou `CLUSTER_NAME`, muda o alvo); kubeconfig em arquivo temporário, e o kubelogin só converte esse arquivo (o `~/.kube/config` e o contexto atual de quem roda não mudam); os scripts de `platform/local` só falam com o contexto `kind-tx02v2-local`; o nome do PostgreSQL, que é um nome DNS global, leva o sufixo da assinatura | quem faz fork roda os scripts na própria máquina e na própria assinatura, onde pode haver clusters, contextos e variáveis de outros projetos, e o lab de outro fork | check `policy-scripts`; `require_lab_cluster` (`scripts/lib/azure.sh`) e `require_lab_context` (`scripts/lib/local.sh`); teste `defaults_are_lab_friendly` | bloqueante |
| SUP-01 | Ferramentas do harness com versão e SHA256 fixados; divergência é erro fatal | cadeia de suprimentos | `scripts/install-tools.sh`, `tools/checksums.txt`; `tool-versions` | bloqueante |
| SUP-02 | Toda action fixada por SHA de 40 caracteres com comentário `# vX.Y.Z`; um SHA por action | tags podem ser movidas | `policy-workflows`, `version-consistency` | bloqueante |
| SUP-03 | Providers com `.terraform.lock.hcl` gerado para 4 plataformas (o check exige pelo menos 4 hashes `h1:` por provider); roots iniciam com `-lockfile=readonly` | builds reprodutíveis | `terraform-lockfiles`, `terraform-validate:*` | bloqueante |
| SUP-04 | Chart do ALB Controller conferido por SHA256 e digests das imagens em execução conferidos; imagens do ESO e do devcontainer por digest | nada muda sem um diff | `helm-template`, `contract-platform`, `version-consistency`, `repo-structure`; `platform/install.sh` | bloqueante |
| SUP-05 | trivy só via `scripts/install-tools.sh` (nunca `trivy-action`/`setup-trivy`, GHSA-69fq-xp46-6x23) | incidente de cadeia de suprimentos de março de 2026 | `policy-workflows` | bloqueante |
| SUP-06 | Versões coerentes entre arquivos (ruleset do tflint, hook do gitleaks, tag do ALB, digests do ESO, `required_version`, restrição do azurerm, minor do Kubernetes nos schemas) | uma atualização não fica pela metade | `version-consistency` | bloqueante |
| SUP-07 | Dependabot mensal, minor+patch agrupados, majors separados; majors do azurerm e o hook do gitleaks ignorados de propósito (ver os comentários no arquivo) | nada apodrece em silêncio | `.github/dependabot.yml` | alerta |
| IAC-01 | Terraform não fala com o Kubernetes nem com o diretório do Entra: sem providers `kubernetes`, `helm` ou `azuread` | separação de camadas; erro do v1 | `policy-terraform` | bloqueante |
| IAC-02 | Resource providers registrados pelo argumento `resource_providers_to_register` do provider no bootstrap, nunca pelo recurso `azurerm_resource_provider_registration`; os providers usam `resource_provider_registrations = "none"` e `storage_use_azuread = true`; nada de credencial no bloco do provider ou do backend | erro do v1 (`MissingSubscriptionRegistration`, `use_cli`) | `policy-terraform`; teste `resource_providers_of_the_lab_are_registered` (a lista de namespaces; a ligação da lista com o provider é revisão) | bloqueante |
| IAC-03 | `tags = local.tags` ou `tags = var.tags` em todo recurso cujo schema aceita `tags`; os valores das tags são os do contrato | o azurerm não tem tags padrão; o `leftovers.sh` usa `Project=tx02v2` | `policy-tags`; testes (`defaults_are_lab_friendly` e os de cada módulo) | bloqueante |
| IAC-04 | `timestamp()`/`plantimestamp()` só em recurso com `lifecycle.ignore_changes` do atributo | erro do v1: diff perpétuo | `policy-terraform` | bloqueante |
| IAC-05 | Todo input não booleano validado: CIDRs canônicos e sem sobreposição, subnet do AGC exatamente /24, GUIDs minúsculos, minor do Kubernetes, tamanho de VM fora da série B, contagens de nós | erro cedo, antes de qualquer chamada à Azure | `validations.tftest.hcl` (31 casos) | bloqueante |
| IAC-06 | `trivy config` sem achados HIGH/CRITICAL (simples e com `--tf-vars` do exemplo) | segurança da IaC | `trivy-config`, `trivy-config-tfvars` | bloqueante |
| IAC-07 | tflint (preset recommended + ruleset azurerm) sem nenhum issue; ignore inline só com motivo (o motivo é conferido na revisão) | qualidade da IaC | `tflint`; revisão de PR | bloqueante |
| IAC-08 | HCL formatado e válido em todos os roots e módulos | revisões legíveis | `terraform-fmt`, `terraform-validate:*` | bloqueante |
| IAC-09 | Sem o add-on Azure Policy no AKS | custo; erro do v1 (Gatekeeper brigando com o add-on) | `policy-terraform`; teste `control_plane` | bloqueante |
| IAC-10 | Ampliação de papéis Azure, rede, RBAC ou CORS só com justificativa no PR | revisões conscientes | template de PR | processo |
| K8S-01 | Manifests da plataforma validados com kubeconform estrito e schemas fixados por commit | manifest inválido não chega ao cluster | `kubeconform` | bloqueante |
| K8S-02 | Namespace com Pod Security `restricted`, Role com as regras exatas do contrato (plurais do ALB 1.12.2), RoleBinding com um `User` por object ID e ClusterSecretStore (`azurekv`, `WorkloadIdentity`, só `dx02v2`); o renderizador recusa entradas inválidas | menor privilégio no cluster | `contract-platform` | bloqueante |
| K8S-03 | Values do ALB Controller (namespace `azure-alb-system`, CRDs do Gateway API, SecurityPolicy, client ID só por `--set-string`) e do ESO (ServiceAccount `external-secrets`, label do Workload ID, 3 imagens por digest) | as credenciais federadas dependem desses nomes | `contract-platform`, `helm-template` | bloqueante |
| K8S-04 | Antes do destroy, o `platform/uninstall.sh` apaga Gateways, rotas, políticas do ALB e Services `LoadBalancer` e espera; falha alto | nada do Kubernetes prende recursos da Azure | ordem em `terraform-destroy.yml`; `policy-workflows` exige o passo | bloqueante |
| APP-01 | Contrato com o dx02v2 versionado: as 15 chaves de `contract.tf` e a lista do harness são iguais, e cada chave tem uma linha na tabela de `docs/CONTRATO.md`; mudanças em PRs coordenados | os dois lados evoluem juntos | `contract-appconfig`; `contract_keys_in_app_configuration` | bloqueante |
| APP-02 | `dx02v2-gha-deploy` e cada `app_deployer_principal_ids` recebem Repository Writer apenas em `dx02v2/api` e `dx02v2/web`, `Azure Kubernetes Service Cluster User Role` e `App Configuration Data Reader` | quem faz deploy tem o mesmo acesso, nada além | `app_deployers_get_the_roles_of_the_deploy_identity` | bloqueante |
| CUSTO-01 | Budget mensal (padrão 25 na moeda de faturamento) com alertas Actual 50/80/100 % e Forecasted 100 %; e-mails obrigatórios e validados | quem paga é você | `terraform/bootstrap/budget.tf` + `budget.tftest.hcl` | alerta |
| CUSTO-02 | Padrões econômicos: AKS Free, 2 nós `Standard_D2als_v6` (autoscaler 1–3), PostgreSQL B1ms com 32 GB e 7 dias de backup, sem HA, ACR Standard para ABAC por repositório, App Configuration Free, logs do plano de controle desligados | menor custo compatível com o controle de acesso e a política de admissão ensinados | `defaults_are_lab_friendly` e testes dos módulos | bloqueante |
| CUSTO-03 | Destroy falha alto (sem `\|\| true`/`continue-on-error`), segue para o `terraform destroy` mesmo quando o `platform/uninstall.sh` falha e termina com `scripts/leftovers.sh` com `if: always()` | erro do v1: destroy que engolia erros; um uninstall que falha não pode deixar o lab de pé cobrando | `scripts/destroy.sh`, `terraform-destroy.yml`; check `destroy-flow` (CLIs simuladas); `policy-workflows` | bloqueante |
| CUSTO-04 | Rodada em nuvem termina com destroy no mesmo dia, `leftovers.sh` local como Owner e relatório `cloud_run_report` | evita custo esquecido | `docs/RUNBOOK.md` | processo |
| CI-01 | O CI é o harness: jobs só chamam `make <alvo>` | o que passa local passa no CI | revisão de PR; `ci.yml` | processo |
| CI-02 | Sem `continue-on-error: true`, `\|\| true`, `\|\| echo` ou `\|\| :` em workflows; sem `sed` em arquivos Terraform | gates honestos; erro do v1 | `policy-workflows` | bloqueante |
| CI-03 | `permissions: contents: read` no topo, `timeout-minutes`, `concurrency`, `ubuntu-24.04`, `persist-credentials: false` | menor privilégio e previsibilidade | `policy-workflows` | bloqueante |
| CI-04 | `HARNESS_STRICT=1` no CI: todo SKIP vira FAIL | nada é pulado em silêncio | `ci.yml`, `scripts/harness.sh` | bloqueante |
| CI-05 | Workflows de nuvem: só `workflow_dispatch` (o plan também em PR, com guarda), environment `lab`, primeiro passo `Check ...` que valida as variáveis (o check exige o passo; o conteúdo é revisão), login só por OIDC, confirmação digitada no destroy | ações caras exigem intenção | `policy-workflows` | bloqueante |
| CI-06 | Plans com `-lock=false` (a identidade do plan só lê o state); apply e destroy mantêm o lock | o plan não consegue gravar o lease | `policy-workflows` | bloqueante |
| CI-07 | O resumo e o artefato do plan e o resumo do apply trocam GUIDs e o sufixo por `<GUID>`/`<SUFFIX>`; os workflows mascaram os IDs de tenant, assinatura, client e do deploy e o sufixo | logs de repositório público | `terraform-plan.yml`, `terraform-apply.yml` | processo |
| CI-08 | CI semanal agendado (segunda 06:00 UTC) | detecta ignores vencidos, charts e URLs que mudaram | `ci.yml` | alerta |
| CI-09 | O job `e2e` (lab local) roda em todo PR e precisa estar verde antes do merge | a plataforma local é provada, não só renderizada | `ci.yml`; check obrigatório do ruleset | bloqueante |
| LOC-01 | O lab local nunca fala com uma nuvem: sem provider de nuvem nem backend remoto em `terraform/envs/local`; Docker só por socket local; `random_password` só nesse root (credenciais descartáveis desta máquina) | o lab é grátis e seguro de rodar | `policy-terraform`; validação de `docker_host` (`terraform-test:envs/local`) | bloqueante |
| LOC-02 | Contêineres do lab local com o label `tx02v2.lab=local`; só o registry publica porta, e em 127.0.0.1 (`5002`); nada privilegiado | nada fica exposto nem esquecido | `terraform-test:envs/local`, `policy-terraform`, `scripts/leftovers-local.sh` | bloqueante |
| LOC-03 | Charts do lab local fixados por versão e SHA256 do `.tgz`; imagens por digest; Services só ClusterIP (exceto os Gateways, criados em runtime) | supply chain e nenhuma UI exposta (erro do v1: Grafana e Argo CD públicos) | `helm-template-local`, `local-versions`, `platform/local/install.sh` (recusa SHA256 diferente) | bloqueante |
| LOC-04 | Políticas do Gatekeeper em `deny`, webhook `Fail` para o app, cada política com casos aceitos e recusados | no v1 as políticas ficavam em `dryrun` sem audit | `policy-gator`; sonda `policies` do `e2e` | bloqueante |
| LOC-06 | O lab local confere a máquina antes de criar algo (daemon do CLI = daemon do provider, rede do lab sem sobrepor rede ou rota da máquina, porta do registry livre) e nunca age num lab que o seu `LOCAL_STATE_DIR` não criou; `make clean` só mexe sob o diretório do Makefile | quem faz fork roda o lab na própria máquina, com VPN, outros contêineres e outro lab | check `local-preflight` (`scripts/tests/local-preflight.sh`, `docker`, `kind` e `ip` simulados); `scripts/local-lab.sh` (`preflight`, `require_own_lab`); `Makefile` | bloqueante |
| LOC-05 | Toda peça da plataforma local tem uma sonda com tráfego ou chamada real; o `e2e` sempre destrói e confere sobras | só se afirma o que foi provado | `platform/local/check.sh`, `scripts/local-lab.sh e2e` | bloqueante (no job `e2e`) |
| MUD-01 | `main` protegido por ruleset: PR obrigatório, checks `static` e `test` estritos, sem force-push | toda mudança passa pelo harness | `.github/rulesets/main.json` + `scripts/repo-guardrails.sh`; `policy-workflows` confere os contextos | bloqueante (depois de publicado) |
| MUD-02 | Ignore de scanner só com `statement` e `expired_at` em até ~7 meses | exceções revisadas | `trivyignore-policy` | bloqueante |
| MUD-03 | Scripts de entrada com bit executável no índice do git | commits do Windows perdem o bit | `repo-structure` (antes do primeiro commit, só um aviso com o comando `git add --chmod=+x`) | bloqueante (depois do primeiro commit) |
| MUD-04 | Conventional Commits; um assunto por PR; CHANGELOG `[Unreleased]` atualizado | histórico legível | `CONTRIBUTING.md`; template de PR (CHANGELOG) | processo |
| DOC-01 | README e docs só afirmam o que é verificado, com os rótulos exatos; sem auto-elogios, emojis ou links para os repositórios v1; README com até 250 linhas; finais de linha LF | honestidade (erro do v1) | `repo-structure`; revisão | bloqueante |
| DOC-02 | Docs atualizadas na mesma mudança do código | docs não envelhecem | template de PR | processo |
| AGT-01 | Agentes de IA nunca executam ações que alteram a nuvem sem pedido humano explícito na tarefa | dinheiro e segurança | `AGENTS.md` | processo |
| AGT-02 | Agentes não enfraquecem gates nem adicionam ignores sem justificativa e validade | o harness só vale se for respeitado | `AGENTS.md`; checks acima | processo |
| AGT-03 | Agentes param e perguntam nos casos listados em `AGENTS.md` | decisões caras são humanas | `AGENTS.md` | processo |

| K8S-05 | Argo CD do perfil full fica em ClusterIP; o app-of-apps só sincroniza o projeto `platform`; o projeto `dx02v2` limita repositório, namespace e tipos; o deployer pode fazer `get`, `watch` e `patch` só na Application `dx02v2` | GitOps não amplia o acesso do deployer às outras Applications | `helm-template-full`, `contract-platform`, teste de teardown | bloqueante |
| SEC-20 | Velero usa Workload ID, Storage Account sem shared key, firewall de rede `Deny` que libera só a subnet dos nós AKS, container privado e `Storage Blob Data Contributor` somente no container; lifecycle apaga blobs após 35 dias | nenhuma credencial estática nem acesso de dados amplo | `terraform/envs/lab/tests/roles.tftest.hcl`, `terraform/envs/lab/tests/network.tftest.hcl`, `helm-template-full` | bloqueante |
| SEC-21 | Kyverno admite imagens do app só por digest e com atestação Sigstore de promoção assinada pelo workflow `deploy-azure.yml` do fork; política `ImageValidatingPolicy` usa `failurePolicy: Fail` e `validationActions: Deny` | imagem não promovida não inicia no namespace do app | `image-admission-policy`, `helm-template-full`, CI do dx02v2 | bloqueante |
| K8S-06 | O perfil full usa Istio waypoint para o tráfego L7 do app; políticas preservam mTLS no mesh e permitem só o caminho HTTP do AGC pela subnet delegada | tráfego direto não contorna a camada L7 e a exceção da borda não abre outros serviços | `contract-platform`, `helm-template-full`, CI do dx02v2 | bloqueante |

## Exceções

Uma exceção é um ignore de scanner. Para adicionar uma:

1. Confirme que o achado é uma escolha deliberada do lab (não um defeito a corrigir).
2. Adicione a entrada em `.trivyignore.yaml` com `id`, `paths` (o mais restrito possível),
   `statement` (por que é aceitável e o que compensa o risco) e `expired_at` em até ~7 meses.
3. Explique a exceção no PR. O check `trivyignore-policy` rejeita entradas sem justificativa, sem
   validade, vencidas ou longas demais; o trivy deixa de aplicar uma entrada vencida.

Exceções atuais (verificado em 2026-10-16): `AZU-0010` (sem bypass AzureServices na conta Velero,
porque nenhum serviço Azure precisa acessá-la; válida até 2027-04-16), `AZU-0012` (endpoint público da
conta do state) e `AZU-0013` (endpoint público do Key Vault), estes dois exigidos por runners
hospedados sem IP fixo (`docs/ARQUITETURA.md`, ADR 20; válidos até 2027-04-30). Achados MEDIUM/LOW
conhecidos e aceitos, que não falham o scan: purge protection desligada (`AZU-0016`, de propósito),
segredos sem data de expiração (`AZU-0017`), parâmetros de log de servidor PostgreSQL
(`AZU-0019`, `AZU-0021`, `AZU-0024`), logs do AKS no Azure Monitor (`AZU-0040`, opcionais), logging
e replicação geográfica da conta do state
(`AZU-0057`, `AZU-0058`), chaves gerenciadas pelo cliente (`AZU-0060`, `AZU-0067`; ADR 21), cluster
privado (`AZU-0065`; ADR 19) e add-on Azure Policy (`AZU-0066`; IAC-09).

## Limites (o que NÃO é garantido)

- Nada do v2 rodou na Azure: os testes usam um provider azurerm mockado e provam a configuração, não
  que a Azure aceita cada chamada nem que os recursos funcionam juntos.
- `tx02v2-gha-apply` é poderoso dentro de `tx02v2-lab` (Contributor, papéis de dados de Key Vault e
  App Configuration, atribuição de papéis limitada por ABAC). Por isso: assinatura dedicada,
  environment `lab` com revisor obrigatório e deploy só a partir de `main`.
- `tx02v2-gha-plan` não lê plano de dados (nenhum valor de segredo do Key Vault, nenhuma chave da
  App Configuration, nenhuma credencial do AKS): o plan roda com `-refresh=false` e mostra a diferença
  contra o último state, não drift (ADR 14). Quem pode criar branches no repositório pode, numa PR,
  alterar o workflow do plan, mas só alcança o que o `Reader` do `tx02v2-lab` e o state alcançam.
  Forks não recebem a credencial.
- IDs de assinatura, tenant e client aparecem como entradas dos workflows. A Azure não os trata como
  segredo; os workflows os mascaram e os resumos os substituem, mas use uma assinatura dedicada.
- Variáveis de repositório (`LAB_*`, `AZURE_*`) aparecem nos logs. Não coloque nelas nada privado: as
  listas de pessoas e endereços de quem opera o lab são secrets (SEC-15).
- Com runners hospedados, a API do AKS fica aberta para `0.0.0.0/0` durante a rodada (o token do
  Entra ID e o RBAC continuam obrigatórios).
- O chart do ALB Controller não aceita digests: o `platform/install.sh` confere o SHA256 do chart antes
  e os digests das imagens depois que os pods sobem — uma imagem diferente já teria rodado quando o
  script falha e pede a remoção.
- O budget só avisa; ele não para recursos.
- `scripts/leftovers.sh` cobre os tipos de recurso que o lab usa. No workflow, a identidade do apply
  só enxerga o que pode ler: as listagens no escopo da assinatura podem voltar só os recursos de
  `tx02v2-lab`, sem erro, e o que ela não pode ler de jeito nenhum aparece como `UNCHECKED`. A
  checagem completa é local, como Owner.
- O papel `Reader` do ALB Controller no grupo de nós não é atribuído (desvio documentado em
  `docs/ARQUITETURA.md`, não testado em nuvem).
- O schema do ClusterSecretStore no kubeconform é de 2026-06-02 (`docs/HARNESS.md`).
- O tier Free da App Configuration aceita 1.000 requisições por dia; depois responde 429 até a
  meia-noite UTC.
- O lab local prova a plataforma num nó kind, não na Azure; o cloud-provider-kind usa o socket do
  Docker (cria contêineres): rode o lab local só numa máquina descartável ou no CI (`docs/LAB_LOCAL.md`).
  A rodada completa roda no job `e2e` do CI, obrigatório no ruleset.
- Os namespaces `istio-system`, `monitoring-agents` e `chaos-mesh` do lab local são `privileged` por
  necessidade dos componentes; o webhook do Gatekeeper não avalia os namespaces da plataforma (para que
  ela suba mesmo com o Gatekeeper fora do ar).

## Como verificar

```bash
make tools                 # ferramentas fixadas em .tools/
HARNESS_STRICT=1 make verify
scripts/harness.sh list    # todos os checks e estágios
scripts/leftovers.sh       # depois de um destroy (az login como Owner da assinatura)
```
