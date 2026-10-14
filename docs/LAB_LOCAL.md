# Lab local

O lab v1 tinha uma plataforma completa — Istio, Prometheus/Grafana/Alertmanager, Loki, Argo CD,
Gatekeeper, Trivy Operator, backup, Chaos Mesh — mas só existia na nuvem, e boa parte nunca funcionou
de verdade (`docs/LICOES_APRENDIDAS.md`). O lab local constrói essa plataforma inteira no Docker da sua
máquina, com Terraform, e prova cada peça com tráfego ou chamadas reais. Nada aqui fala com a Azure.
É a mesma plataforma do lab local do `tx01v2`, com os nomes do `tx02v2` e os gêmeos Azure abaixo.

Status: `verificado no CI` (job `e2e`, 26 sondas, 2026-10-13) e `verificado localmente` (rodada
completa do zero no mesmo dia: apply, perfil `full`, destroy sem sobras).

## O que é criado

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
| core | Gateway API 1.6.3 (standard), Istio 1.31.1 ambient (istiod, istio-cni, ztunnel, GatewayClass `istio`), cert-manager 1.21.2 + ClusterIssuer `lab-ca`, External Secrets 2.12.0 + ClusterSecretStore `local-secrets`, metrics-server 0.9.0, contrato `lab-system/lab-contract` | todos |
| observability | kube-prometheus-stack 92.3.0 (Prometheus 3.15, Alertmanager 0.34 → `alert-sink`, Grafana 13.2 só ClusterIP, kube-state-metrics, node-exporter), Loki 3.6 (single binary), Alloy 1.20 | `observability`, `full` |
| operations | Argo CD 3.5.5, Gatekeeper 3.23.1 + políticas, Trivy Operator 0.35, Velero 1.18 (plugin AWS/S3 → emulador; só no lab local), Chaos Mesh 2.8.4 | `operations`, `full` |

Pod Security: `restricted` em todos os namespaces, menos `istio-system`, `monitoring-agents` e
`chaos-mesh` (`privileged`: mexem na rede ou nos processos do nó) e `trivy-system` (`baseline`, com
aviso de `restricted`). O namespace do app, `dx02v2`, é `restricted`, faz parte do mesh ambient e tem
as constraints do Gatekeeper em `deny`.

## Como rodar

Precisa de Docker com 8 GB de memória para o perfil `full` (o perfil `core` cabe em 3 GB), além das
ferramentas de `make tools`. Linux, WSL 2 ou o devcontainer.

```bash
make e2e                          # up + sondas + down (sempre destrói, também depois de falha)
LOCAL_PROFILE=core make local-up  # só a base; observability e operations são as outras camadas
make local-check                  # sondas do que estiver instalado
make local-down                   # destroy + scripts/leftovers-local.sh
scripts/local-lab.sh status       # contêineres e nós do lab
export KUBECONFIG="$(scripts/local-lab.sh kubeconfig)"   # kubectl contra o lab
```

O devcontainer tem Docker próprio (Docker-in-Docker): lá dentro, os comandos acima funcionam sem
ajuste (`LOCAL_PROFILE=core make e2e` verificado localmente em 2026-10-14). Dentro de um contêiner
que usa o Docker do host (docker.sock montado), exporte `LOCAL_KIND_INTERNAL=1`: o script entra na
rede do lab e usa o endereço interno da API.

Para abrir o Grafana: `kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80`,
usuário `admin`, senha `terraform -chdir=terraform/envs/local output -raw grafana_admin_password` (com o
`TF_DATA_DIR` de `scripts/local-lab.sh`). O Argo CD não tem usuário admin local: inspecione as
`Application` com kubectl.

## O que as sondas provam (`platform/local/check.sh`)

| Área | Sonda |
|---|---|
| Banco | conexão `verify-full` com a CA do lab funciona; texto puro é recusado |
| Mesh | cliente com identidade permitida chega ao serviço (mTLS pelo ztunnel); outra identidade é recusada pela `AuthorizationPolicy`; cliente fora do mesh é recusado pelo `STRICT` |
| Borda | Gateway `Programmed` com endereço do load balancer emulado; HTTPS verificado contra a CA do lab; um `X-Request-Id` externo chega intacto ao backend (`EnvoyFilter` `gateway-preserve-request-id`, o que o smoke do dx02v2 no kind espera; o AGC na Azure gera o próprio `x-request-id`); HTTP → 301 |
| Segredos | ExternalSecret no namespace `dx02v2` vira Secret com as cinco chaves do contrato |
| Métricas | `kubectl top nodes` (metrics-server) |
| Observabilidade | alvos de kube-state-metrics, node-exporter, apiserver e kubelet coletados; `PrometheusRule` sintética chega ao `alert-sink` pelo Alertmanager; logs do namespace da sonda aparecem no Loki; Grafana saudável e só ClusterIP |
| GitOps | commit no servidor git sincronizado pelo Argo CD; segundo commit reconciliado; objeto apagado recriado (self-heal) |
| Políticas | pod fora das regras recusado pelas cinco constraints de pod; pod conforme aceito; Service NodePort recusado |
| Registry e scan | imagem enviada ao registry é baixada pelo nó; o Trivy Operator (modo ClientServer, com o Trivy server embutido) gera ConfigAuditReport e VulnerabilityReport |
| Backup | backup Velero de um namespace, namespace apagado, restore com os dados |
| Chaos | hipótese: com 2 réplicas, matar um pod não derruba o serviço (pelo menos 38 de 40 requisições) |

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
- Logs, métricas e backups vivem dentro do lab (retenções de horas) e somem no destroy.
