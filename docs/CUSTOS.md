# Custos do lab

Estimativa do custo por hora, por dia e de um mês esquecido com os padrões do lab em `eastus2`, para
decidir antes de criar qualquer coisa. Os valores da tabela base são **preços de referência (Azure
Retail Prices API, 2026-10-11); o acréscimo do perfil full usa a consulta de 2026-10-16** — confira a
calculadora oficial antes de cada rodada: preços de tabela pay-as-you-go em US$, sem impostos, sem
transferência de dados e sem créditos. O budget do bootstrap
usa a moeda de faturamento da assinatura. Nada disto foi medido numa fatura real: a v2 nunca rodou
em nuvem (`não executado em nuvem (v2)`).

## Estimativa por componente (padrões, eastus2)

| Componente | Quantidade (padrão) | Preço de referência | US$/hora | US$/dia | US$/mês esquecido (730 h) |
|---|---|---|---|---|---|
| AKS, plano de controle no tier Free | 1 cluster | sem cobrança de gerenciamento (página oficial); ver o medidor abaixo | 0,000 | 0,00 | 0,00 |
| Nós `Standard_D2als_v6` (Linux) | 2 (autoscaler 1–3) | US$0,0804/h por nó | 0,161 | 3,86 | 117,38 |
| Disco de SO dos nós (Premium SSD P4, 30 GB) | 2 | US$4,80/mês por disco | 0,013 | 0,32 | 9,60 |
| Load Balancer Standard de saída do AKS | 1 (até 5 regras) | US$0,025/h + US$0,005/GB processado | 0,025 | 0,60 | 18,25 |
| IP público Standard da saída do AKS | 1 | US$0,005/h | 0,005 | 0,12 | 3,65 |
| Application Gateway for Containers **com WAF** (padrão) | 1 AGC + 1 frontend + 1 associação + ~1 unidade de capacidade | US$0,031 + 0,018 + 0,216 + 0,014 por hora | 0,279 | 6,70 | 203,67 |
| Application Gateway for Containers sem WAF (`enable_waf = false`) | o mesmo | US$0,017 + 0,010 + 0,120 + 0,008 por hora | (0,155) | (3,72) | (113,15) |
| PostgreSQL Flexible Server `B_Standard_B1ms` | 1 | US$0,017/h | 0,017 | 0,41 | 12,41 |
| Armazenamento do PostgreSQL | 32 GB | US$0,115/GB-mês | 0,005 | 0,12 | 3,68 |
| Backup do PostgreSQL (7 dias, LRS) | até 32 GB | sem custo até 100 % do armazenamento provisionado; acima, US$0,095/GB-mês | 0,000 | 0,00 | 0,00 |
| ACR Standard (ABAC por repositório) | 1 registry (10 GB incluídos) | US$0,6666/dia | 0,0278 | 0,67 | 20,28 |
| Zona DNS privada do PostgreSQL | 1 | US$0,50/zona-mês + US$0,40/milhão de consultas | 0,001 | 0,02 | 0,50 |
| Key Vault Standard | 2 segredos | US$0,03 por 10 mil operações | ~0 | ~0 | centavos |
| App Configuration Free | 1 store | sem custo (limite de 1.000 requisições por dia) | 0,000 | 0,00 | 0,00 |
| Traces do app: Application Insights + workspace `tx02v2-lab-traces` (contrato v2, sempre) | volume do lab (alguns MB por rodada); teto de 0,5 GB/dia em cada um | o mesmo preço do Log Analytics abaixo (ingestão por GB; a franquia de 5 GB/mês cobre o volume do lab) | ~0 (até 0,058 no teto) | ~0 (até 1,38) | ~0 |
| Log Analytics (opcional, `enable_control_plane_logs = false`) | teto de 0,5 GB/dia | US$2,76/GB depois de 5 GB/mês grátis por conta de faturamento; 31 dias de retenção sem custo | (até 0,058) | (até 1,38) | (até ~28; ~42 se a franquia já estiver usada) |
| State do Terraform (Blob Hot LRS, bootstrap) | poucos KB | US$0,0184/GB-mês + operações | ~0 | ~0 | centavos |
| Managed identities, VNet, NSG, budget | — | sem cobrança | 0,000 | 0,00 | 0,00 |
| **Total com WAF (padrão)** | | | **~0,534** | **~12,81** | **~389** |
| **Total sem WAF** | | | **~0,410** | **~9,84** | **~299** |

Hipóteses: 1 frontend, 1 associação e cerca de 1 unidade de capacidade de AGC (tráfego de
laboratório; o consumo real depende de conexões, throughput e computação); 2 nós o tempo todo (o
autoscaler pode descer a 1 com pouca carga ou subir a 3); logs do plano de controle desligados
(padrão).

O ACR Standard é necessário para RBAC com ABAC por repositório. Em relação ao Basic usado antes,
o preço de referência sobe US$0,50/dia (US$0,0208/h ou cerca de US$15,21 por 730 horas). As tabelas
usam o preço pay-as-you-go consultado na [Azure Retail Prices API](https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices).

Leituras rápidas:

- Uma rodada de 3 horas (apply → plataforma → deploy → smoke → destroy) custa cerca de US$1,60 com
  WAF e US$1,23 sem. Load Balancer, AGC e PostgreSQL cobram hora parcial como hora cheia.
- Esquecido ligado, o lab custa cerca de US$12,81 por dia com WAF: o budget padrão (25 na moeda de
  faturamento) passa de 50 % em cerca de um dia e de 100 % em cerca de dois.
- O Application Gateway for Containers com WAF é o maior item: ~54 % do total; só a associação
  (US$0,216/h) é ~42 %. O WAF custa US$0,124/h a mais que o AGC sem WAF. Os nós são ~31 %.

## O medidor "FreeTierInfrastructureCost" do AKS

### Continuidade R9: HA e segunda região

O `core` preserva a conta acima. O perfil `ha` usa PostgreSQL General Purpose `D2ads_v5` (2 vCores):
a Azure Retail Prices API retornou **US$0,178/h por servidor em eastus2** em 2026-10-17. HA cobra
principal e standby: **US$0,356/h**, mais duas cópias de 32 GiB de SSD (~US$0,010/h usando a tarifa
da tabela base). O banco HA custa cerca de **US$0,366/h**, contra ~US$0,022/h do banco `core`;
acréscimo de **~US$0,344/h**, **US$1,03 por três horas**, ou **US$251 por 730 horas**.

O `dr` reserva ainda um segundo AKS com nós/discos/saída, ACR Standard, AGC/WAF, segredos/config,
backup e réplica PostgreSQL zonal. Usando os preços da tabela base como referência para o destino
`centralus`, o segundo ambiente é aproximadamente **US$0,695/h** (substituir B1ms por D2ads_v5).
Principal HA + secundário ficam em **~US$1,57/h**, **~US$4,72 por três horas** ou **~US$1.148 por
730 horas**, antes de egress entre regiões, geo backups, volumes/observabilidade full, restaurações,
operações e impostos. O destino pode ter outra tarifa: esta é uma hipótese de orçamento, não uma
fatura. Mesmo sem tráfego, standby, réplica e nós continuam cobrados.

A retenção maior aumenta os blocos de backup usados; geo backup usa preço diferente do LRS.
O PITR/geo restore cria servidor novo e cobra computação/armazenamento enquanto ele existir.
Confira [preços oficiais de PostgreSQL](https://azure.microsoft.com/pricing/details/postgresql/flexible-server/)
e a [API Retail Prices](https://learn.microsoft.com/rest/api/cost-management/retail-prices/azure-retail-prices)
na região/moeda da assinatura antes do apply. A v2 ainda não foi medida em uma conta Azure.

O que foi verificado em 2026-10-11:

- A Azure Retail Prices API lista, no serviço Azure Kubernetes Service, um medidor com
  `skuName = FreeTierInfrastructureCost` e `meterName = FreeTierInfrastructureCost Uptime SLA`, de
  US$0,05/h (US$0,0625/h em algumas regiões), com vigência a partir de 2026-10-01, em 61 regiões,
  incluindo `eastus2`.
- A [página oficial de preços do AKS](https://azure.microsoft.com/pricing/details/kubernetes-service/)
  e o documento
  [Free, Standard and Premium pricing tiers](https://learn.microsoft.com/azure/aks/free-standard-pricing-tiers)
  continuam dizendo que o tier Free não cobra o gerenciamento do cluster (só os recursos usados) e não
  mencionam esse medidor nem uma mudança de cobrança.

O que **não** foi possível verificar: o que o medidor cobre e se ele é cobrado de um cluster no tier
Free. Isso só se confirma rodando um cluster e olhando o Cost Management. Se ele se aplicar, soma
US$0,05/h (US$1,20/dia, US$36,50 num mês esquecido): totais de ~0,563/h com WAF e ~0,439/h sem.
Na primeira rodada em nuvem, agrupe o custo por medidor no Cost Management depois de algumas horas,
registre o resultado no `cloud_run_report` e atualize esta seção.

## Tamanho dos nós

Segundo a documentação do AKS (verificado em 2026-10-11), VMs da série B não são suportadas em system
node pools, e tamanhos com menos de 2 vCPUs e 4 GB podem ser recusados
([Quotas, VM size restrictions and region availability in AKS](https://learn.microsoft.com/azure/aks/quotas-skus-regions);
a página "Use system node pools" fala em 4 vCPUs, e o lab segue o mínimo da página de restrições —
não verificado em nuvem). Por isso o padrão é `Standard_D2als_v6` (2 vCPU, 4 GiB, x86-64), o tamanho
mais barato que atende a essas regras em `eastus2`, e a validação de `node_vm_size` recusa a série B
(teste `rejects_a_b_series_system_pool`). Preços Linux de alternativas na mesma consulta:

| Tamanho | vCPU / memória | US$/hora |
|---|---|---|
| `Standard_D2als_v6` (padrão) | 2 / 4 GiB | 0,0804 |
| `Standard_D2als_v7` | 2 / 4 GiB | 0,0804 |
| `Standard_F2s_v2` | 2 / 4 GiB | 0,0846 |
| `Standard_D2ls_v5` | 2 / 4 GiB | 0,0850 |
| `Standard_D2as_v5` | 2 / 8 GiB | 0,0860 |

A série Dalsv6 só aceita imagens com NVMe e geração 2 e não tem disco temporário (por isso
`node_os_disk_type = "Managed"`). Antes da rodada, confira se o tamanho está liberado para a sua
assinatura e região:
`az vm list-skus --location eastus2 --size Standard_D2als_v6 --all --output table` (coluna
Restrictions) e `az vm list-usage --location eastus2 --output table` (cota de vCPU da família). O
lab precisa de 4 vCPUs da família, 6 durante um upgrade (surge de 1 nó) ou com o autoscaler em 3.

## Custo adicional do perfil full

O perfil full também exige um domínio registrado pelo operador. O Terraform cria uma zona Azure DNS
pública e um CNAME; a zona e as consultas são cobradas à parte, conforme a
[tabela oficial do Azure DNS](https://azure.microsoft.com/en-us/pricing/details/dns/). O preço do
registro do domínio e da renovação no registrador não está incluído. O certificado Let's Encrypt não
exige compra, mas o desafio HTTP-01 depende de delegação pública e do AGC ligado. Consulte os preços
da sua oferta antes da rodada; o total abaixo não inclui DNS nem domínio.

O perfil full precisa de mais memória que o perfil core. Para os valores de referência de 2026-10-16, o runbook usa dois nós `Standard_D2as_v5` (2 vCPU, 8 GiB), a US$0,086/h por nó, em vez de dois `Standard_D2als_v6` (2 vCPU, 4 GiB) a US$0,0804/h. O acréscimo é US$0,0112/h para o pool, calculado com preços pay-as-you-go de eastus2. O perfil full também usa ACR Standard para habilitar ABAC por repositório.

| Cenário | US$/hora | US$/dia | US$/mês (730 h) |
|---|---:|---:|---:|
| Perfil full com WAF, sem discos de dados | ~0,545 | ~13,08 | ~397,88 |
| Perfil full sem WAF, sem discos de dados | ~0,421 | ~10,10 | ~307,35 |
| PVCs `managed-csi` do full: 3 × E3 (16 GiB), 2 × E1 (4 GiB) | ~0,0058 | ~0,14 | ~4,20 |
| **Perfil full com WAF e PVCs** | **~0,551** | **~13,22** | **~402,08** |
| **Perfil full sem WAF e PVCs** | **~0,427** | **~10,24** | **~311,55** |
| Rodada de 3 horas com WAF e PVCs | — | — | ~1,65 por rodada |
| Rodada de 3 horas sem WAF e PVCs | — | — | ~1,28 por rodada |

Os valores de compute somam US$0,0112/h ao total do perfil core e mantêm as demais hipóteses da tabela anterior. Os cinco PVCs pedem 36 GiB e provisionam aproximadamente 56 GiB em Standard SSD LRS: Prometheus 12 GiB, Loki 10 GiB e Tempo 10 GiB usam E3 (16 GiB); Alertmanager e Grafana, com 2 GiB cada, usam E1 (4 GiB). A estimativa de US$4,20/mês usa os preços de base de `eastus2`, não inclui transações de disco nem armazenamento e operações do Blob, tráfego, logs opcionais ou eventual cobrança do medidor `FreeTierInfrastructureCost`. Discos Azure são cobrados por hora e pelo tier que acomoda a capacidade solicitada ([Managed Disks](https://azure.microsoft.com/pricing/details/managed-disks/)); AKS `managed-csi` usa discos gerenciados. O `platform/uninstall.sh` apaga os PVCs de monitoramento e os discos correspondentes no teardown. Use `LAB_NODE_VM_SIZE=Standard_D2as_v5` e `LAB_NODE_COUNT=2` antes do plan/apply, e mantenha os mesmos valores até o destroy. O full usa Grafana e Prometheus dentro do cluster; não cria Azure Managed Grafana nem Azure Managed Prometheus. São preços estimados, não custos medidos; nenhuma rodada cloud foi executada.

### Requests renderizados e capacidade de referência

O `helm-template-full` renderiza os 16 pacotes de charts fixados e chama `scripts/platform-sizing.sh 2`.
Em 2026-10-16, os manifests somaram os requests da tabela abaixo. DaemonSets contam uma instância
por nó; Prometheus e Alertmanager contam seus `spec.resources`. O check compara esses números com
esta linha para que a estimativa não se separe dos charts.

| Perfil | Requests dos charts | Nós de referência | Capacidade nominal antes de reservar recursos para AKS e para o app |
|---|---:|---|---|
| full | 1335 mCPU / 3808 MiB | 2 × `Standard_D2as_v5` (2 vCPU, 8 GiB cada) | 4000 mCPU / 16384 MiB; os charts usam cerca de 33% da CPU e 22% da memória nominal |

Os valores são requests de CPU e memória dos charts, não uso medido nem capacidade `allocatable`. Os
charts também pedem armazenamento: Prometheus 12 GiB, Alertmanager 2 GiB, Grafana 2 GiB, Loki 10 GiB
e Tempo 10 GiB, todos em `managed-csi`; os discos gerenciados são cobrados enquanto existirem. Eles não incluem
pods de sistema do AKS, a aplicação, nem o Azure Monitor Agent. O tamanho `D2as_v5` fornece margem
de memória para esses componentes; o render não prova que o cluster sobe ou que a margem é
suficiente em runtime. A escolha continua `não executado em nuvem (v2)`.

### Comparação de observabilidade gerenciada (R4.2)

Com as demais premissas e os dois nós do perfil `full` mantidos, a opção no cluster custa cerca de
US$1,57 por uma rodada de 3 horas com WAF (US$1,20 sem WAF), como na tabela anterior. A alternativa
gerenciada mantém essa base de infraestrutura e acrescenta os serviços abaixo. Não atribuí economia
de nó por remover charts, pois requests do agente gerenciado e capacidade `allocatable` não foram
medidos.

| Item gerenciado, `eastus2` | Referência de preço consultada em 2026-10-16 | Custo em uma rodada de 3 horas |
|---|---:|---:|
| Azure Managed Grafana Standard X1 (2 Standard Units) | US$0,034246 por unidade-hora + US$6 por usuário ativo/mês | ~US$0,2055 de instância + US$6 por usuário ativo/mês |
| Azure Monitor Managed Prometheus | US$0,16 por 10 milhões de amostras ingeridas; US$0,001 por 10 milhões processadas em consultas | depende do volume da rodada |
| Log Analytics | US$2,76/GB após os primeiros 5 GB mensais gratuitos da conta de faturamento | depende do volume billable da rodada |

Assim, mantendo a infraestrutura full, o cenário gerenciado começa em cerca de US$1,78 por 3 horas,
mais usuários ativos e os volumes de métricas/logs; o cenário no cluster fica em cerca de US$1,57.
O custo de usuário pode ser cobrado uma vez por mês, não proporcionalmente à duração da rodada.
Não contabilizei a oferta promocional de 30 dias do Grafana. O custo exato gerenciado requer amostras
e ingestão observadas; a documentação da Microsoft recomenda estimar com volumes medidos e a
calculadora oficial. Nenhuma das opções foi executada nesta nuvem.

## Cenários do v1 (Azure, dezembro de 2025 a janeiro de 2026)

Das notas do v1 (detalhes em `docs/LICOES_APRENDIDAS.md`, seção 17), para comparação; não servem como
orçamento atual:

| Cenário do v1 | Valor nas notas |
|---|---|
| Base em modo AKS (2 nós Standard_D2s_v3, Load Balancer Basic, state) | ~US$272/mês |
| Application Gateway WAF_v2 com 2 instâncias | ~US$246/mês de base, US$250–350/mês na média |
| Application Gateway Standard_v2 sem WAF | ~US$125/mês |
| Crédito do Free Trial | ~US$200 por 30 dias, estimado em 25 dias de modo AKS |

A lição continua valendo: a entrada com WAF custa tanto quanto o resto do lab somado. O v2 troca o
Application Gateway v2 pelo AGC (cobrado por hora, sem instâncias) e deixa o WAF desligável.

## Dicas

- Destrua no mesmo dia e rode `scripts/leftovers.sh` localmente, como Owner da assinatura, até não
  haver nada `BILLABLE` (`docs/RUNBOOK.md`).
- `enable_waf = false` economiza US$0,124/h, mas o app fica sem WAF; o dx02v2 aplica o overlay sem a
  WebApplicationFirewallPolicy quando `waf/policy-id` é `none`.
- Não suba `node_count` nem troque o tamanho dos nós sem refazer a conta; o autoscaler pode chegar a
  3 nós sozinho.
- Os traces do app (Application Insights `tx02v2-lab-traces`) existem em toda rodada: o volume do lab
  é de poucos MB, e `log_daily_quota_gb` (0,5 GB/dia) limita o pior caso; os spans das sondas de
  saúde (`/healthz`, `/readyz`) nem são criados.
- `enable_control_plane_logs = true` cria um workspace do Log Analytics com teto de 0,5 GB/dia; a
  franquia de 5 GB/mês é da conta de faturamento inteira, não deste lab.
- Créditos do Free Trial escondem a fatura: confira o Cost Management nas primeiras horas de cada
  rodada e mantenha os alertas do budget.
- Um Key Vault apagado fica em soft delete por 7 dias (o nome fica reservado, sem cobrança); a purga
  exige permissão no escopo da assinatura (`docs/ARQUITETURA.md`).

## R10: capacidade e FinOps

Veja [FinOps e escala](FINOPS.md) para a topologia kind HA, carga/HPA/PDB, OpenCost, VPA Off, Spot opt-in, pre?os regionais, or?amento/expira??o e limpeza. Constru??o para fork; nada executado na nuvem (v2).
