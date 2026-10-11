# Custos do lab

Estimativa do custo por hora, por dia e de um mês esquecido com os padrões do lab em `eastus2`, para
decidir antes de criar qualquer coisa. Todos os valores são **preços de referência (Azure Retail
Prices API, 2026-10-11) — confira a calculadora oficial** antes de cada rodada: preços de tabela
pay-as-you-go em US$, sem impostos, sem transferência de dados e sem créditos. O budget do bootstrap
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
| ACR Basic | 1 registry (10 GB incluídos) | US$0,1666/dia | 0,007 | 0,17 | 5,07 |
| Zona DNS privada do PostgreSQL | 1 | US$0,50/zona-mês + US$0,40/milhão de consultas | 0,001 | 0,02 | 0,50 |
| Key Vault Standard | 2 segredos | US$0,03 por 10 mil operações | ~0 | ~0 | centavos |
| App Configuration Free | 1 store | sem custo (limite de 1.000 requisições por dia) | 0,000 | 0,00 | 0,00 |
| Log Analytics (opcional, `enable_control_plane_logs = false`) | teto de 0,5 GB/dia | US$2,76/GB depois de 5 GB/mês grátis por conta de faturamento; 31 dias de retenção sem custo | (até 0,058) | (até 1,38) | (até ~28; ~42 se a franquia já estiver usada) |
| State do Terraform (Blob Hot LRS, bootstrap) | poucos KB | US$0,0184/GB-mês + operações | ~0 | ~0 | centavos |
| Managed identities, VNet, NSG, budget | — | sem cobrança | 0,000 | 0,00 | 0,00 |
| **Total com WAF (padrão)** | | | **~0,513** | **~12,30** | **~374** |
| **Total sem WAF** | | | **~0,389** | **~9,33** | **~284** |

Hipóteses: 1 frontend, 1 associação e cerca de 1 unidade de capacidade de AGC (tráfego de
laboratório; o consumo real depende de conexões, throughput e computação); 2 nós o tempo todo (o
autoscaler pode descer a 1 com pouca carga ou subir a 3); logs do plano de controle desligados
(padrão).

Leituras rápidas:

- Uma rodada de 3 horas (apply → plataforma → deploy → smoke → destroy) custa cerca de US$1,54 com
  WAF e US$1,17 sem. Load Balancer, AGC e PostgreSQL cobram hora parcial como hora cheia.
- Esquecido ligado, o lab custa cerca de US$12,30 por dia com WAF: o budget padrão (25 na moeda de
  faturamento) passa de 50 % em cerca de um dia e de 100 % em cerca de dois.
- O Application Gateway for Containers com WAF é o maior item: ~54 % do total; só a associação
  (US$0,216/h) é ~42 %. O WAF custa US$0,124/h a mais que o AGC sem WAF. Os nós são ~31 %.

## O medidor "FreeTierInfrastructureCost" do AKS

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
- `enable_control_plane_logs = true` cria um workspace do Log Analytics com teto de 0,5 GB/dia; a
  franquia de 5 GB/mês é da conta de faturamento inteira, não deste lab.
- Créditos do Free Trial escondem a fatura: confira o Cost Management nas primeiras horas de cada
  rodada e mantenha os alertas do budget.
- Um Key Vault apagado fica em soft delete por 7 dias (o nome fica reservado, sem cobrança); a purga
  exige permissão no escopo da assinatura (`docs/ARQUITETURA.md`).
