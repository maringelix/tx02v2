# Lab local

O lab v1 tinha uma plataforma completa — Istio, Prometheus/Grafana/Alertmanager, Loki, Argo CD,
Gatekeeper, Trivy Operator, backup, Chaos Mesh — mas só existia na nuvem, e boa parte nunca funcionou
de verdade (`docs/LICOES_APRENDIDAS.md`). O lab local constrói essa plataforma inteira no Docker da sua
máquina, com Terraform, e prova cada peça com tráfego ou chamadas reais. Nada aqui fala com a Azure.
É a mesma plataforma do lab local do `tx01v2`, com os nomes do `tx02v2` e os gêmeos Azure abaixo.

Status: `verificado no CI` (job `e2e`, 34 sondas) e `verificado localmente` (2026-10-13: rodada
completa do zero, perfil `full` com as 26 sondas de então; 2026-10-14: perfil `observability`, com os
traces e o Slack). O tamanho `small` (abaixo) é `verificado no CI` pelo job `e2e-platform-small`
do dx02v2: a plataforma `full` com o app, com o Docker limitado a 7 GB.

O v1 parou nos "próximos passos" (DR multi-região, FinOps, chaos, observabilidade com OpenTelemetry).
Aqui dois deles existem e são provados: traces com OpenTelemetry (Collector, Tempo, spans dos Gateways
do Istio, spanmetrics com exemplars, Grafana ligando logs, métricas e traces) e experimentos de chaos
com hipótese (pod kill, latência de rede, stress de CPU e memória). Os alertas também vão para o
Slack, como no v1, mas o webhook nunca fica em arquivo versionado.

## O que é criado

O R8 também cria o Gateway `dx02v2-waypoint` e vincula o namespace do app a ele. O tráfego do
Gateway de entrada passa pelo waypoint para aplicar autorização L7; o instalador espera a condição
`Programmed` antes de instalar os componentes seguintes. `platform/local/check.sh` confere o
Gateway e o vínculo do namespace; o CI de dx02v2 prova a comunicação real do app e a política L7.

`terraform/envs/local` (providers `kreuzwerker/docker` 4.6, `hashicorp/tls` 4.4, `hashicorp/random`
3.9; state local fora do repositório, em `~/.local/state/tx02v2-local`):

| Na Azure | No lab local | Endereço |
|---|---|---|
| VNet | rede Docker `tx02v2-local` (`10.251.0.0/24`; metade de cima para o nó e os load balancers) | — |
| AKS 1.36 | cluster kind `tx02v2-local` (Kubernetes 1.36, kindnet com NetworkPolicy) | API em 127.0.0.1 (porta aleatória) |
| ACR (Azure Container Registry) | registry (CNCF Distribution 3.1.2) | push em `localhost:5002`, pull como `registry.tx02v2.local` |
| Azure Database for PostgreSQL Flexible Server 17 com `require_secure_transport = on` | PostgreSQL 17, `hostssl` + SCRAM, texto puro recusado, certificado da CA do lab | `10.251.0.11`, `db.tx02v2.local` |
| Bundle `azure-pg-ca` (raízes DigiCert/Microsoft) | CA do lab (ECDSA P-256, 30 dias), gerada pelo provider `tls` | — |
| Blob Storage (backups) | Versity S3 Gateway 1.8.0, que fala a API do S3, não a do Blob (buckets `tx02v2-local-velero`, `tx02v2-local-db-backups`) | `http://10.251.0.12:7070` |
| Application Gateway for Containers (ALB Controller) | cloud-provider-kind 0.12.0: um Envoy por Service `LoadBalancer` | metade de cima da rede |
| GitHub (origem do GitOps) | Soft Serve 0.12.3: push por SSH com a chave do state, leitura anônima por HTTP | `10.251.0.13` |

Nomes, rede (`10.251.0.0/24`) e porta do registry (`5002`) são diferentes dos do lab local do `tx01v2`
(`10.250.0.0/24`, `5001`): os labs de pares diferentes não colidem na mesma máquina (memória à parte).

Todos os contêineres e volumes levam o label `tx02v2.lab=local`. Só o registry publica porta, e só em
127.0.0.1. As credenciais (senha do banco, token de admin, chaves do emulador de objetos, senha do
Grafana, chave SSH) são geradas pelo Terraform e ficam no state local: valem só para esta máquina e
somem no destroy.

`platform/local/install.sh` instala, nesta ordem (versões e SHA256 em `platform/local/versions.env`,
imagens por digest em `platform/local/values/`):

| Camada | Componentes | Perfil |
|---|---|---|
| core | Gateway API 1.6.3 (experimental, para o retry do exercício R8 no waypoint), Istio 1.31.1 ambient (istiod, istio-cni, ztunnel, GatewayClass `istio`), cert-manager 1.21.2 + ClusterIssuer `lab-ca`, External Secrets 2.12.0 + ClusterSecretStore `local-secrets`, metrics-server 0.9.0, contrato `lab-system/lab-contract` | todos |
| observability | kube-prometheus-stack 92.3.0 (Prometheus 3.15 com exemplars, Alertmanager 0.34 → `alert-sink` e Slack, Grafana 13.2 só ClusterIP, kube-state-metrics, node-exporter), Loki 3.6 (single binary), Alloy 1.20, Tempo 3.1 (single binary), OpenTelemetry Collector 0.162 (OTLP → Tempo + spanmetrics), `Telemetry` do Istio (spans dos Gateways) | `observability`, `full` |
| operations | Argo CD 3.5.5, Gatekeeper 3.23.1 + políticas, Trivy Operator 0.35, Velero 1.18 (plugin AWS/S3 → emulador; só no lab local), Chaos Mesh 2.8.4 | `operations`, `full` |

Pod Security: `restricted` em todos os namespaces, menos `istio-system`, `monitoring-agents` e
`chaos-mesh` (`privileged`: mexem na rede ou nos processos do nó) e `trivy-system` (`baseline`, com
aviso de `restricted`). O namespace do app, `dx02v2`, é `restricted`, faz parte do mesh ambient e tem
as constraints do Gatekeeper em `deny`.

## Como rodar

Precisa de Docker com 8 GB de memória para o perfil `full`, ou 7 GB com `LOCAL_SIZE=small` (abaixo; o
perfil `core` cabe em 3 GB), além das ferramentas de `make tools`. Linux, WSL 2 ou o devcontainer.

```bash
make e2e                          # up + sondas + down (sempre destrói, também depois de falha)
LOCAL_PROFILE=core make local-up  # só a base; observability e operations são as outras camadas
LOCAL_SIZE=small make local-up    # a plataforma inteira com menos memória (7 GB de Docker, abaixo)
make local-check                  # sondas do que estiver instalado
make local-down                   # destroy + scripts/leftovers-local.sh
scripts/local-lab.sh status       # contêineres e nós do lab
export KUBECONFIG="$(scripts/local-lab.sh kubeconfig)"   # kubectl contra o lab
```

O kubeconfig do lab é um arquivo próprio (`$LOCAL_STATE_DIR/kubeconfig`): o `~/.kube/config` da
máquina nunca é usado nem alterado. Os scripts de `platform/local` recusam qualquer contexto que não
seja `kind-tx02v2-local`, também quando rodam sozinhos, porque o `uninstall.sh` apaga todo Gateway e
todo Service `LoadBalancer` do cluster que alcança (check `policy-scripts`).

O devcontainer tem Docker próprio (Docker-in-Docker): lá dentro, os comandos acima funcionam sem
ajuste (`LOCAL_PROFILE=core make e2e` verificado localmente em 2026-10-14). Dentro de um contêiner
que usa o Docker do host (docker.sock montado), exporte `LOCAL_KIND_INTERNAL=1`: o script entra na
rede do lab e usa o endereço interno da API.

Para abrir o Grafana: `kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80`,
usuário `admin`, senha `terraform -chdir=terraform/envs/local output -raw grafana_admin_password` (com o
`TF_DATA_DIR` de `scripts/local-lab.sh`). Em Explore, o datasource Tempo abre um trace pelo id; num
trace, "Logs for this span" leva às linhas do Loki com o mesmo `trace_id`, e os exemplars dos gráficos
do Prometheus levam ao trace. O Argo CD não tem usuário admin local: inspecione as `Application` com
kubectl.

Alertas no Slack: crie um incoming webhook no seu workspace e suba o lab com
`LOCAL_SLACK_WEBHOOK_URL=https://hooks.slack.com/services/... make local-up`. Os alertas `warning` e
`critical` vão para o canal; sem a variável, o receptor Slack posta no `alert-sink` (é o que o CI testa).
O webhook vai para o Secret `monitoring/alertmanager-slack` pelo stdin do kubectl, nunca para arquivos
ou logs.

## Tamanhos (`LOCAL_SIZE`)

`LOCAL_SIZE=small` (o padrão é `default`) instala os mesmos componentes com menos memória: o
`helm_install` põe `platform/local/values/small/<chart>.yaml` por último, então os tamanhos dele valem
sobre os outros values. Os componentes continuam os mesmos (as sondas dos apps usam quase todos), e o
padrão já tem uma réplica de cada.

| Chart | No tamanho `small` |
|---|---|
| kube-prometheus-stack | Prometheus com retenção de 2 h (padrão 6 h), 20 mil exemplars (padrão 100 mil) e limite de 640 MiB; sem os endpoints cAdvisor e probes do kubelet, sem os histogramas do apiserver e sem os grupos de regras padrão que leem essas séries (os alvos que as sondas procuram continuam); Grafana sem o alerting unificado (o lab alerta pelo Alertmanager) e sem instalar plugins na partida, limite de 512 MiB |
| Loki, Tempo, Alloy | limites de 320, 320 e 200 MiB; Tempo com retenção de 1 h (padrão 6 h) |
| OpenTelemetry Collector | limite de 192 MiB (o chart deriva dele o `GOMEMLIMIT` e o `memory_limiter`) |
| Argo CD | menos workers (5 de status, 2 de operação, um render por vez no repo-server; o lab tem uma Application) e limites de 320, 256 e 192 MiB |
| Gatekeeper | auditoria a cada 5 minutos (padrão 1) e só dos tipos que as constraints usam (sem isso, cada rodada lista pelo apiserver todos os tipos do cluster), limite de 384 MiB |
| Trivy Operator | um scan job por vez, limite de 320 MiB no operador |
| Velero | limite de 256 MiB |

Os componentes em Go recebem `GOMEMLIMIT` abaixo do limite (o Prometheus 3 e o chart do Collector já o
derivam do limite), para o coletor de lixo trabalhar antes do OOM kill. O plano de controle também:
o `scripts/local/kind-cluster.sh` acrescenta `terraform/envs/local/kind-config-small.yaml` à config do
kind (`GOMEMLIMIT` no apiserver, no controller-manager e no etcd, pelo `extraEnvs` do kubeadm v1beta4).
Trocar o tamanho de um lab de pé pede `make local-down` antes, porque o cluster existente é
reaproveitado. O check `helm-template-local` renderiza cada chart também com o overlay, aplica as
mesmas regras e falha se o overlay trocar uma imagem ou citar um chart que não existe.

Quanto a plataforma `full` com o app do dx02v2 precisa (memória do Docker, sem swap):

| Tamanho | Docker | Resultado |
|---|---|---|
| `default` | runner do CI, 16 GB | passa (jobs `e2e` daqui e `e2e-platform` do dx02v2) |
| `small` | 7 GB (CI, Docker-in-Docker, 2026-10-15) | passa: as 18 sondas em cerca de 15 minutos, memória anônima de 4,35 GiB |

O par 01 mediu também o tamanho padrão em 7 GB (falha por thrashing) e o `small` em 6 GB (a sonda de
rollout perde requisições) e em 8 GB (passa): `docs/LAB_LOCAL.md` do tx01v2. O tamanho `small` fica
em 7 GB, decisão do Bruno em 2026-10-15 (a meta da R1.8 era 6 GB). O job `e2e-platform-small` do
dx02v2 repete a prova em todo PR. Picos de memória no job (working set, 2026-10-15):
apiserver 1333 MiB, Grafana 368 MiB, controller do Argo CD 262 MiB, Prometheus 237 MiB,
Trivy Operator 199 MiB, etcd 158 MiB e os dois pods do Gatekeeper, 244 MiB.

## O que as sondas provam (`platform/local/check.sh`)

| Área | Sonda |
|---|---|
| Banco | conexão `verify-full` com a CA do lab funciona; texto puro é recusado |
| Mesh | cliente com identidade permitida chega ao serviço (mTLS pelo ztunnel); outra identidade é recusada pela `AuthorizationPolicy`; cliente fora do mesh é recusado pelo `STRICT` |
| Borda | Gateway `Programmed` com endereço do load balancer emulado; HTTPS verificado contra a CA do lab; um `X-Request-Id` externo (texto livre ou UUID) chega intacto ao backend (`EnvoyFilter` `gateway-preserve-request-id`, o que o smoke do dx02v2 no kind espera; o AGC na Azure gera o próprio `x-request-id`); HTTP → 301 |
| Segredos | ExternalSecret no namespace `dx02v2` vira Secret com as cinco chaves do contrato |
| Métricas | `kubectl top nodes` (metrics-server) |
| Observabilidade | alvos de kube-state-metrics, node-exporter, apiserver e kubelet coletados; `PrometheusRule` sintética chega ao `alert-sink` pelo Alertmanager e ao receptor Slack no formato de mensagem do Slack (com `LOCAL_SLACK_WEBHOOK_URL`: notificações entregues, nenhuma com falha); logs do namespace da sonda aparecem no Loki; Grafana saudável e só ClusterIP |
| Traces (OpenTelemetry) | um span OTLP/HTTP enviado ao Collector aparece no Tempo; o Gateway continua um `traceparent` W3C de entrada, passa o próprio span ao backend e o reporta ao Tempo; o spanmetrics gera as séries RED no Prometheus com um exemplar que carrega o trace id; o Grafana alcança o Tempo e liga logs → traces (campo derivado do Loki) e métricas → traces (exemplars) |
| GitOps | commit no servidor git sincronizado pelo Argo CD; segundo commit reconciliado; objeto apagado recriado (self-heal) |
| Políticas | pod fora das regras recusado pelas cinco constraints de pod; pod conforme aceito; Service NodePort recusado |
| Registry e scan | imagem enviada ao registry é baixada pelo nó; o Trivy Operator (modo ClientServer, com o Trivy server embutido) gera ConfigAuditReport e VulnerabilityReport |
| Backup | backup Velero de um namespace, namespace apagado, restore com os dados |
| Chaos | hipóteses: com 2 réplicas, matar um pod não derruba o serviço (pelo menos 38 de 40 requisições); com 100 ms a mais de latência de rede em todos os pods (`NetworkChaos`), pelo menos 19 de 20 requisições passam e a mediana sobe pelo menos 80 ms (a falha é real); com stress de CPU e memória dentro de cada contêiner (`StressChaos`), pelo menos 38 de 40 requisições passam, nenhum contêiner reinicia e o pico de CPU aparece no metrics-server |

## Limites (o que o lab local não prova)

- Nada da Azure: Entra ID, Workload ID, managed identities e credenciais federadas, Application Gateway
  for Containers e a política de WAF reais, Key Vault, App Configuration, PostgreSQL Flexible Server,
  quotas e custo continuam `não executado em nuvem (v2)`. O lab local mostra o alvo da plataforma; a
  camada de plataforma em nuvem ainda instala só o ALB Controller e o ESO (`planejado` para os demais
  add-ons no AKS).
- A borda local (Istio Gateway com HTTPS da CA do lab) não é o AGC: na Azure o listener é HTTP na
  porta 80 (HTTPS `planejado`), o WAF fica no AGC e o `x-request-id` é gerado por ele.
- O emulador de objetos fala a API do S3, então o Velero usa o plugin AWS/S3 só aqui; o Blob Storage
  real (plugin Azure do Velero) não é exercitado.
- Um nó só: sem alta disponibilidade, sem PodDisruptionBudget testado contra drenagem de nó.
- O cloud-provider-kind precisa do socket do Docker (cria contêineres Envoy): rode o lab só numa
  máquina descartável ou no CI.
- O mirror do Trivy Operator e o mapeamento `registry.tx02v2.local` existem só no lab local.
- Logs, métricas, traces e backups vivem dentro do lab (retenções de horas) e somem no destroy.
- O tamanho `small` foi provado com as 18 sondas do dx02v2. As 34 sondas daqui rodam no CI só no tamanho
  padrão: `LOCAL_SIZE=small make e2e` não é verificado.
- Sem `LOCAL_SLACK_WEBHOOK_URL` o CI prova o receptor Slack e o formato da mensagem, não a entrega a um
  workspace de verdade.
