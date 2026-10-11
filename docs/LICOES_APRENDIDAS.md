# Lições aprendidas do lab Azure v1 (dezembro de 2025 a janeiro de 2026)

Este documento resume o que falhou no lab Azure v1 (repositórios tx02 e dx02, numa subscription Free Trial), por que falhou e como foi contornado.
Serve de referência para operar e evoluir o tx02v2/dx02v2 sem repetir os mesmos erros.
Identificadores, nomes únicos, hosts, IPs e segredos das notas foram substituídos por placeholders.

O lab público tx02v2 foi redesenhado a partir destas lições: AKS integrado ao Microsoft Entra ID, com Workload ID para os pods; managed identities federadas via OIDC do GitHub no lugar de segredos de service principal; PostgreSQL Flexible Server com acesso privado; Key Vault com External Secrets; Application Gateway for Containers com WAF via Gateway API, porque o ingress-nginx foi aposentado em março de 2026; resource providers registrados no bootstrap; budget desde o primeiro dia; destroy seguido de verificação de sobras; e CI que não precisa de credenciais de nuvem.

Cada lição segue **Sintoma → Causa → Correção → Recomendação**. A Correção descreve o que foi feito no v1; quando as notas não registram correção, isso aparece explicitamente. O marcador **Desatualizado (out/2026)** indica versão, serviço ou prática que mudou desde as notas; confira a documentação oficial antes de depender dele. Os valores de custo estão reunidos na seção 17.

## 1. Restrições e cotas do Free Trial

### 1.1 Free Trial não é o mesmo que "serviços gratuitos"

- **Sintoma:** a criação do PostgreSQL Flexible Server falhou com `LocationIsOfferRestricted` ("Offer is restricted for subscriptions in this region") em westus2, eastus e centralus; em janeiro de 2026 os planos voltaram a prever PostgreSQL `B_Standard_B1ms` como "free tier", sem revalidar o bloqueio.
- **Causa:** a oferta Free Trial bloqueia serviços e regiões que a lista pública de serviços gratuitos não menciona; ter crédito não significa ter acesso ao serviço.
- **Correção:** troca do banco para Azure SQL Database (seção 7).
- **Recomendação:** provar cada serviço com um deploy mínimo na subscription real antes de fechar a arquitetura e registrar o resultado com data; o upgrade para pay-as-you-go remove as restrições da oferta e mantém o crédito restante até 30 dias após o cadastro.

### 1.2 SKU de nó e região do AKS

- **Sintoma:** `InvalidTemplateDeployment` por violação de policy com `Standard_D2s_v3` em westus2 e eastus, e com `Standard_DC2s_v3` em westus2.
- **Causa:** restrição de tamanhos de VM por oferta e região.
- **Correção:** nós `standard_dc2s_v3` (2 vCPU, 8 GB, série de computação confidencial) em eastus, o único par aceito; o cluster subiu em cerca de 5 minutos.
- **Recomendação:** antes de fixar `node_size`, rodar `az vm list-skus --location <REGION> --size <SKU> --all --output table` (coluna Restrictions) e `az vm list-usage --location <REGION> --output table`, e versionar o par região/SKU validado.

### 1.3 Cota de vCPU e limite de IP público

- **Sintoma:** os planos de janeiro pediam 3 nós de 2 vCPU e o troubleshooting sugeria abrir chamado por "+10 vCPUs da família B"; o LoadBalancer do Grafana falhou com `PublicIPCountLimitReached`.
- **Causa:** cotas baixas na oferta; subscriptions Free Trial não são elegíveis para aumento de cota ou de limite.
- **Correção:** Grafana acessado por `kubectl port-forward`, com orientação de reaproveitar o IP do ingress e apagar IPs sem uso.
- **Recomendação:** dimensionar dentro da cota contando os nós extras de upgrade (surge); um único IP público de entrada; se a cota não bastar, o caminho é o upgrade para pay-as-you-go, não o chamado de suporte.

## 2. Custos

### 2.1 Estimativas contraditórias e "custo zero"

- **Sintoma:** documentos da mesma época estimavam a mesma base em US$ 0 ("100% free tier"), em US$ 35 a 65/mês e em cerca de US$ 272/mês; AKS, PostgreSQL B1ms e ACR Basic apareciam como US$ 0.
- **Causa:** números copiados entre guias sem consulta de preço e confusão entre consumir crédito e não pagar.
- **Correção:** nenhuma registrada nas notas; as estimativas nunca foram reconciliadas.
- **Recomendação:** estimar pela Azure Retail Prices API ou pela calculadora oficial, datar cada preço e conferir o consumo real no Cost Management nas primeiras horas de cada ciclo de apply.

### 2.2 A camada de entrada dominava o custo

- **Sintoma:** o Application Gateway WAF_v2 com 2 instâncias custava sozinho tanto quanto, ou mais que, todo o restante do lab (seção 17).
- **Causa:** o SKU v2 cobra hora fixa mais capacity units, 24x7, mesmo sem tráfego.
- **Correção:** parâmetro `deploy_app_gateway` no workflow, orientação de destruir o gateway fora de uso e Standard_v2 sem WAF como alternativa.
- **Recomendação:** tratar a entrada como componente que se destrói de forma independente; no v2 o maior item é o Application Gateway for Containers com WAF, cobrado por hora.

### 2.3 Budget só como intenção

- **Sintoma:** o limite de R$ 400 existia apenas no texto das notas e "configurar alertas de custo" ficou em próximos passos; o crédito de R$ 1.078,95 (cerca de US$ 200) foi estimado para uns 25 dias em modo AKS.
- **Causa:** budget fora do bootstrap.
- **Correção:** nenhuma registrada nas notas.
- **Recomendação:** budget da subscription criado no bootstrap, com alertas de valor real e previsto (por exemplo 50, 80 e 100%); o budget fica na moeda de faturamento e só avisa, não bloqueia gastos.

### 2.4 Franquia de telemetria contada duas vezes

- **Sintoma:** a estratégia de logs descontava 5 GB/mês grátis de cerca de 24 GB/mês, e a de APM descontava outros 5 GB grátis para o Application Insights.
- **Causa:** o Application Insights baseado em workspace fatura a ingestão no Log Analytics, e a franquia de 5 GB/mês é por conta de faturamento.
- **Correção:** nenhuma registrada nas notas.
- **Recomendação:** um único orçamento de ingestão, consulta semanal à tabela `Usage`, sampling na aplicação e exclusão de namespaces ruidosos na coleta.

## 3. Terraform, state e registro de providers

### 3.1 Registro de resource providers

- **Sintoma:** a etapa de registro falhava porque dois `az provider register --namespace ... --wait` foram colados na mesma linha, sem quebra, e a lista de namespaces variava entre guias.
- **Causa:** registro improvisado dentro do workflow de apply, sem lista única, com o provider configurado com `skip_provider_registration = true`.
- **Correção:** um comando por linha, com `--wait`, para Microsoft.Network, Compute, Storage, ContainerService, OperationalInsights e Sql; ContainerRegistry e DBforPostgreSQL entraram depois.
- **Recomendação:** registrar no bootstrap, a partir de uma lista versionada e com uma identidade que tenha permissão para isso; o pipeline de apply só confere `registrationState`.
- **Desatualizado (out/2026):** `skip_provider_registration` foi substituído por `resource_provider_registrations` no azurerm 4.0, e a major atual do provider é a 5 (5.9.0, verificado em 2026-10-11).

### 3.2 Plan parado esperando input

- **Sintoma:** `terraform plan` no CI ficava mais de 30 minutos sem saída até o timeout; no log aparecia o prompt de `var.tags`.
- **Causa:** variáveis sem valor e Terraform aguardando entrada interativa num runner sem terminal.
- **Correção:** as 24 variáveis passadas por `-var`, incluindo `-var="tags={}"`, e timeout de 15 minutos.
- **Recomendação:** `-input=false` em todo comando do CI, para falhar em segundos, e um `.tfvars` por ambiente no repositório em vez de listas de `-var` repetidas em plan, apply e import.

### 3.3 Plan e apply divergentes

- **Sintoma:** o plan usava `use_aks=false` e o apply `use_aks=true`; `db_version` era `12.0` (a versão do SQL Server reaproveitada para PostgreSQL) num e `17` no outro; só o apply recebia os `TF_VAR_*` sensíveis e só o plan usava `-parallelism=10`.
- **Causa:** cada workflow com a sua cópia de variáveis; o `use_aks=false` sobrou do isolamento do timeout de dezembro, quando o módulo de banco virou condicional "temporariamente".
- **Correção:** valores sincronizados à mão nos dois workflows.
- **Recomendação:** uma única fonte de variáveis e um apply que consome o arquivo de plano salvo (`plan -out=tfplan`, `apply tfplan`) gerado no job anterior e aprovado no environment protegido, com artefato de retenção curta porque o plano contém valores sensíveis.

### 3.4 Lock órfão do state

- **Sintoma:** `Error acquiring the state lock` com "state blob is already locked" depois de cancelar um workflow ou estourar o timeout.
- **Causa:** a lease do blob não é liberada quando o job é interrompido.
- **Correção:** `az storage blob lease break` manual e, depois, um step que quebrava a lease antes de todo plan, com `continue-on-error: true`.
- **Recomendação:** não quebrar lock automaticamente, porque isso anula a proteção contra execuções simultâneas; usar `concurrency` do GitHub Actions por state e `terraform force-unlock <LOCK_ID>` manual depois de confirmar que nada está rodando.

### 3.5 Erros de HCL que um validate local pegaria

- **Sintoma:** `Missing false expression in conditional` (heredoc dentro de ternário), `Unsupported attribute` ao ler `virtual_network_id` de `data.azurerm_subnet`, `vars map does not contain key "admin_username"` no `templatefile()`, `Duplicate required providers configuration` e `Duplicate backend configuration`, `An argument named "use_cli" is not expected here` no backend, e `terraform fmt -check` saindo com código 3.
- **Causa:** código enviado sem validação local; `versions.tf` e `provider.tf` com blocos duplicados.
- **Correção:** `join()` no lugar dos heredocs, data source da VNet, chave incluída no template, remoção de `versions.tf`, `use_cli` só no provider e `terraform fmt -recursive`.
- **Recomendação:** pre-commit e CI sem credenciais com `fmt -check`, `init -backend=false`, `validate` e tflint antes de qualquer job que toque a nuvem, e um único bloco `terraform {}`.
- **Desatualizado (out/2026):** os workflows fixavam Terraform 1.6.0; o v2 usa 1.16.5 (verificado em 2026-10-11).

### 3.6 Import de recursos criados fora do Terraform

- **Sintoma:** `A resource with the ID ".../servers/<SQL_SERVER>" already exists` no apply e `Cannot import non-existent remote object` quando o recurso ainda não existia; os guias alternavam entre `module.database.` e `module.database[0].`.
- **Causa:** banco criado no portal e módulo com `count`, que muda o endereço do recurso.
- **Correção:** step de `terraform import` antes do apply, repetindo todas as variáveis e terminando em `|| true`.
- **Recomendação:** blocos `import {}` declarativos no lugar de `terraform import ... || true`, que esconde falhas; melhor ainda, nenhum recurso criado fora do Terraform.

### 3.7 Nomes fixos e documentação divergente do código

- **Sintoma:** bootstrap falhando com "Storage account name already taken"; nome do SQL server preso por 5 a 10 minutos após a exclusão; guias citando `rg-<proj>-<env>` e `aks-<proj>-<env>` enquanto o código criava `<proj>-<env>-rg` e `<proj>-<env>-aks`, além de dois nomes de ACR, VNet 10.0.0.0/16 e 10.1.0.0/16, subnet do gateway 10.0.4.0/24 e 10.0.5.0/24, e container e blob do state com nomes diferentes.
- **Causa:** nomes globais fixos no código e literais copiados para a documentação.
- **Correção:** orientação de trocar à mão a constante `STORAGE_ACCOUNT` no workflow de bootstrap.
- **Recomendação:** sufixo aleatório gerado uma vez e guardado no state para nomes globais (`<STORAGE_ACCOUNT>`, `<ACR_NAME>`, servidor de banco); documentação e scripts leem `terraform output` em vez de repetir literais.

## 4. Identidades e GitHub Actions

### 4.1 Client secret do service principal

- **Sintoma:** `AADSTS7000215: Invalid client secret provided`, primeiro porque o GitHub recebeu o Secret ID (um GUID) em vez do Value, e de novo em janeiro de 2026, já no step de registro de providers, porque o secret expirou ou foi rotacionado; `AADSTS700016: Application not found` quando o SP era removido.
- **Causa:** autenticação por segredo de longa duração copiado para vários repositórios (`AZURE_CREDENTIALS` em JSON e `AZURE_CLIENT_SECRET`), sem dono nem calendário de rotação.
- **Correção:** `az ad sp credential reset` e atualização manual dos secrets em cada repositório.
- **Recomendação:** OIDC do GitHub com managed identity federada, subject restrito a repositório e environment, e nenhum segredo de nuvem guardado no GitHub; a conclusão das notas de que service principal era melhor que managed identity em workflows foi revertida no v2.
- **Desatualizado (out/2026):** `az ad sp create-for-rbac --sdk-auth` está depreciado; os workflows usavam `azure/login@v1` e a versão atual é a v3 (verificado em 2026-10-11); "Azure AD" agora se chama Microsoft Entra ID.

### 4.2 Sessão do azure/login conflitando com o provider

- **Sintoma:** `Authenticating using the Azure CLI is only supported as a User (not a Service Principal)`.
- **Causa:** o step `azure/login` deixava uma sessão de CLI de service principal que o provider azurerm tentava usar.
- **Correção:** remoção do `azure/login`, variáveis `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID` e `ARM_SUBSCRIPTION_ID`, e `use_cli = false`, `use_msi = false` e `use_oidc = false` no provider.
- **Recomendação:** um método de autenticação explícito por job; no v2, `ARM_USE_OIDC=true` com o client ID da managed identity, e backend azurerm com `use_oidc` e `use_azuread_auth` em vez de access key.

### 4.3 Privilégio amplo e chaves estáticas

- **Sintoma:** um SP `Contributor` na subscription inteira, descrito como "least privilege" e compartilhado entre infra e app; state acessado por `ARM_ACCESS_KEY`; ACR com admin user; a correção sugerida para um 403 no Chaos Studio era dar mais Contributor.
- **Causa:** atalhos para destravar o pipeline.
- **Correção:** nenhuma registrada nas notas; Key Vault ficou para "depois do deploy".
- **Recomendação:** uma identidade por função (plan somente leitura, apply, push de imagem com AcrPush) e escopo no menor grupo de recursos possível; storage do state sem chave compartilhada e com `Storage Blob Data Contributor`; Contributor não cria role assignments (AcrPull, Storage Blob Data), o que exige um papel com `Microsoft.Authorization/roleAssignments/write`, de preferência Role Based Access Control Administrator com condição.

### 4.4 Segredos em inputs, notas e literais

- **Sintoma:** senha do admin do Argo CD e webhook do Slack passados como inputs de `workflow_dispatch`; senha do PFX e senhas de exemplo escritas nas notas e sugeridas como valor real; Secrets do Kubernetes criados com `kubectl create secret --from-literal` contendo a senha do banco.
- **Causa:** ausência de cofre e de convenção para segredos.
- **Correção:** nenhuma registrada nas notas.
- **Recomendação:** inputs de workflow não são mascarados, então nunca carregam segredo; Key Vault como fonte única, External Secrets no cluster e gitleaks no CI cobrindo também a documentação.

### 4.5 "Validado" sem tocar na nuvem

- **Sintoma:** relatórios de janeiro declaravam a infraestrutura "100% validada e aprovada para deploy" contando arquivos, módulos e workflows, sem Azure CLI instalada e sem plan contra a subscription; a regra "nunca rodar Terraform local nem criar recursos via az" convivia com gateway configurado por `az` e banco criado no portal.
- **Causa:** validação estrutural tratada como validação funcional.
- **Correção:** nenhuma registrada nas notas.
- **Recomendação:** separar o que roda sem credenciais (fmt, validate, tflint, Checkov, testes) do que exige a nuvem (plan e apply em environment protegido) e registrar sempre o que foi e o que não foi verificado.

## 5. AKS

### 5.1 Tamanho de nó sem fonte única

- **Sintoma:** as notas citam `standard_dc2s_v3` (o que funcionou), `Standard_D2s_v3`, `Standard_DS2_v2` e `Standard_B2s` (2 vCPU, 4 GB) para o mesmo cluster; os requests do Prometheus, do Grafana e do operator foram cortados pela metade para caber em "B2s ou similar".
- **Causa:** valores copiados entre guias sem conferir o que estava deployado.
- **Correção:** nenhuma registrada nas notas.
- **Recomendação:** tamanho de nó numa variável validada contra cota e SKU; somar os requests de todos os add-ons (sidecars do Istio, monitoramento, Argo CD, Gatekeeper, Chaos Mesh) antes de escolher nós de 4 GB; system node pool separado do pool de aplicação.

### 5.2 Versão do Kubernetes fixada sem plano de upgrade

- **Sintoma:** cluster em 1.32 e referência rápida com `az aks upgrade --kubernetes-version 1.32.0`.
- **Causa:** versão escolhida uma vez e copiada entre guias.
- **Correção:** nenhuma registrada nas notas.
- **Recomendação:** escolher a versão com `az aks get-versions --location <REGION>`, habilitar canal de auto-upgrade de patch e de imagem de nó e definir janela de manutenção.
- **Desatualizado (out/2026):** 1.32 está fora do suporte padrão do AKS; a minor GA mais recente é a 1.36, GA desde 2026-06-30 (verificado em 2026-10-11).

### 5.3 Receitas de Kubernetes genérico em componente gerenciado

- **Sintoma:** o troubleshooting do HPA mandava aplicar o manifesto `latest` do metrics-server, e o guia de logs mandava desligar e religar o add-on de monitoramento com `az aks disable-addons`/`enable-addons` quando o agente entrasse em CrashLoopBackOff.
- **Causa:** guias escritos para clusters autogerenciados.
- **Correção:** nenhuma registrada nas notas.
- **Recomendação:** no AKS o metrics-server já é gerenciado; diagnosticar com `kubectl top`, `kubectl get apiservice v1beta1.metrics.k8s.io`, eventos e logs antes de reinstalar qualquer componente.

## 6. Rede, ingress e Application Gateway/WAF

### 6.1 Backend do gateway preso a IPs de nó e NodePorts

- **Sintoma:** backend pool vazio ou com o IP público do NGINX, sem alcançar o ClusterIP; a solução manual foi `az network application-gateway address-pool update --servers <NODE_IP_1> <NODE_IP_2>` e `http-settings update --port <NODEPORT_HTTP>`.
- **Causa:** Application Gateway criado fora do cluster e sem controlador; ele só enxerga endereços da VNet.
- **Correção:** IPs internos dos nós e NodePorts do ingress-nginx, coletados com `kubectl get nodes -o wide` e `kubectl get svc -n ingress-nginx`.
- **Recomendação:** não acoplar a entrada a nós e portas: IPs mudam em scale e upgrade do VMSS, e os NodePorts mudaram quando o serviço foi recriado (32371/31565 em dezembro, 31805/31953 em janeiro); usar um controlador que sincroniza o backend, como o ALB Controller do Application Gateway for Containers.

### 6.2 Health probe devolvendo 404

- **Sintoma:** backends `Unhealthy`, com a probe padrão recebendo 404.
- **Causa:** a probe não enviava o header Host, e o ingress roteia por host.
- **Correção:** `az network application-gateway probe create --host <HOST> --path /` associada ao `http-settings`; com isso os backends ficaram Healthy.
- **Recomendação:** endpoint de saúde dedicado que responde sem depender do host, com a probe declarada no IaC.

### 6.3 Certificado copiado à mão para o gateway

- **Sintoma:** para HTTPS foi preciso exportar `tls.crt` e `tls.key` do Secret do cert-manager, gerar PFX com `openssl pkcs12 -export`, subir com `ssl-cert create` e criar porta 443, listener com SNI, probe e regra HTTPS com prioridade 200.
- **Causa:** TLS terminado no gateway, com o certificado emitido e renovado dentro do cluster.
- **Correção:** passos manuais e plano de cron para re-sincronizar a cada renovação de 90 dias.
- **Recomendação:** terminar TLS onde o certificado é gerenciado (Gateway API com cert-manager, ou certificado no Key Vault referenciado pelo gateway), sem cópia manual de chave privada.
- **Desatualizado (out/2026):** a Let's Encrypt encerrou os e-mails de expiração em 04/06/2025 e anunciou validade de 64 dias a partir de fevereiro de 2027 e de 45 dias em 2028, o que inviabiliza a cópia manual; o `installCRDs=true` do cert-manager deu lugar a `crds.enabled=true`.

### 6.4 Entrada fora do IaC

- **Sintoma:** um workflow de segurança separado do Terraform criava gateway, WAF policy, IP público e subnet, o restante era feito à mão com `az`, e o checklist previa quatro jobs novos com `|| echo "already exists"` para parecerem idempotentes.
- **Causa:** a camada de entrada nasceu fora do Terraform.
- **Correção:** nenhuma registrada nas notas; a automação ficou planejada.
- **Recomendação:** recursos Azure da entrada no Terraform e objetos Kubernetes (Gateway, HTTPRoute, política de WAF) no GitOps, para que o plan mostre drift e o destroy alcance tudo.

### 6.5 WAF em Detection sem data para Prevention

- **Sintoma:** WAF_v2 em Detection; o teste `curl "http://<HOST>/?id=1' OR '1'='1"` só gerava log, e certificados do staging da Let's Encrypt não eram confiáveis no navegador.
- **Causa:** modo inicial escolhido para evitar falsos positivos, sem critério de saída.
- **Correção:** orientação de coletar os logs pelo diagnostic setting `ApplicationGatewayFirewallLog` e de ficar 1 a 2 semanas em Detection.
- **Recomendação:** data e critério para Prevention, exclusões versionadas com justificativa e o mesmo payload de teste esperando 403 depois da troca; no WAF do Application Gateway for Containers só o ruleset DRS 2.1 está disponível (verificado em 2026-10-11).

### 6.6 Muitos IPs públicos e DNS dinâmico

- **Sintoma:** Service do dx02 como LoadBalancer; ingress-nginx, Argo CD e gateway do Istio com IP próprio; tentativa de LoadBalancer para o Grafana; DNS dinâmico (`<HOST>`) atualizado à mão a cada IP novo.
- **Causa:** cada componente exposto separadamente.
- **Correção:** `kubectl port-forward` para as ferramentas de operação.
- **Recomendação:** um único ponto de entrada público, ferramentas internas sem IP público e registro DNS gerenciado pelo IaC e removido no destroy.
- **Desatualizado (out/2026):** o ingress-nginx (chart 4.11.3 no v1) foi aposentado em março de 2026 e o add-on de application routing baseado em NGINX tem suporte só até novembro de 2026 (verificado em 2026-10-11); a anotação `kubernetes.io/ingress.class` já tinha dado lugar a `ingressClassName`; Basic Load Balancer e IP público Basic foram aposentados em 30/09/2025.

## 7. Banco de dados

### 7.1 Azure SQL em outra região e com clique no portal

- **Sintoma:** `ProvisioningDisabled` ("Provisioning is restricted in this region") em eastus; a oferta gratuita só funcionou em westus2, criando servidor e banco no portal com o botão "Apply offer".
- **Causa:** restrição da oferta e um passo de portal que o Terraform não reproduzia.
- **Correção:** servidor e banco criados à mão e importados; AKS em eastus falando com o banco em westus2 por Private Endpoint e zona `privatelink.database.windows.net` vinculada à VNet.
- **Recomendação:** não trocar engine nem região por restrição de oferta sem registrar o custo (latência, tráfego entre regiões, DR); a oferta gratuita é de General Purpose serverless (100.000 vCore-segundos/mês, como a nota registra), mas o Terraform declarava Basic 2 GB, então o primeiro plan após o import precisa ser conferido para não alterar o SKU.

### 7.2 Migração de engine quebrando SQL

- **Sintoma:** a app mostrava `connected: false` com `Incorrect syntax near 'current_user'`.
- **Causa:** após a migração de PostgreSQL para SQL Server, a query usava `CURRENT_USER` com um alias que é palavra reservada no T-SQL.
- **Correção:** `SELECT SYSTEM_USER AS db_user`.
- **Recomendação:** testes de integração contra o mesmo engine e versão da nuvem (container local) e queries parametrizadas; o v2 volta ao PostgreSQL Flexible Server, então a migração inversa exige o mesmo cuidado.

### 7.3 Acesso público e senha espalhada

- **Sintoma:** servidor com acesso público e "Allow Azure services" ligados; senha do admin no GitHub (`AZURE_SQL_PASSWORD` e `TF_VAR_db_password`), no state e em Secret do Kubernetes; falhas `Failed to connect to <SQL_SERVER>.database.windows.net:1433` investigadas com `nslookup` dentro do pod.
- **Causa:** atalhos para fazer a conexão entre regiões funcionar.
- **Correção:** Private Endpoint com a zona privada vinculada à VNet.
- **Recomendação:** acesso público desligado, lembrando que "Allow Azure services" libera conexões de qualquer recurso Azure, inclusive de outros clientes; autenticação Entra com managed identity quando o driver permitir e senha gerada no Key Vault quando não.

## 8. ACR

### 8.1 Admin user e credenciais no GitHub

- **Sintoma:** ACR Basic com admin habilitado e `ACR_USERNAME`/`ACR_PASSWORD` tirados de `terraform output -raw` e gravados como secrets do repositório da aplicação.
- **Causa:** era o jeito mais curto de fazer `docker login` no CI.
- **Correção:** nenhuma registrada nas notas.
- **Recomendação:** `admin_enabled = false`, CI autenticado por OIDC com AcrPush só no registry e nenhuma senha de registry em output ou state.

### 8.2 Registries misturados e ImagePullBackOff

- **Sintoma:** `ImagePullBackOff` com "pull access denied" porque um manifest antigo apontava para o Docker Hub; antes disso, o pull do GHCR dependia de um `imagePullSecret` com PAT.
- **Causa:** três registries e segredos de pull ao longo do lab.
- **Correção:** imagens no ACR e AcrPull para a kubelet identity, sem imagePullSecrets.
- **Recomendação:** um registry só, integração validada com `az aks check-acr --resource-group <RG> --name <AKS> --acr <ACR_NAME>.azurecr.io` e tags imutáveis (SHA do commit) ou digest no lugar de `latest`.

## 9. Observabilidade

### 9.1 kube-prometheus-stack instável em cluster pequeno

- **Sintoma:** Grafana em CrashLoopBackOff por datasource duplicado pelo sidecar; Prometheus Operator preso em ContainerCreating esperando o secret do admission webhook; PVCs atrasando; `helm upgrade --install --wait --timeout=15m` travando.
- **Causa:** provavelmente jobs de hook que não concluíam e pods que não ficavam prontos num cluster com pouca memória; a explicação das notas (excesso de verificações do `--wait`) não foi comprovada.
- **Correção:** sidecar de datasources, admission webhooks, TLS do operator e persistência desligados; `--wait` removido, timeout de 5 minutos e requests reduzidos.
- **Recomendação:** manter `--wait` ou `--atomic` e investigar eventos e logs dos jobs de hook em vez de desligar proteções; persistência e retenção decididas de propósito, não por eliminação.

### 9.2 Alertas que não podiam disparar

- **Sintoma:** seis regras para o dx02 (erro acima de 5%, latência acima de 1 s, conexão com banco) enquanto a app não expunha `/metrics`; Alertmanager com receiver `null`; erro `unsupported scheme "" for URL` com o webhook vazio; plano de pôr o webhook direto no values versionado.
- **Causa:** regras escritas antes da instrumentação.
- **Correção:** Slack desligado até existir webhook.
- **Recomendação:** instrumentar primeiro (prom-client ou OpenTelemetry), validar a rota com um alerta sintético e ler o webhook por `api_url_file` de um Secret sincronizado do Key Vault.
- **Desatualizado (out/2026):** `match` nas rotas do Alertmanager foi substituído por `matchers`.

### 9.3 Grafana com credenciais padrão

- **Sintoma:** Grafana com o usuário e a senha padrão do chart, acessado por port-forward depois que o LoadBalancer falhou.
- **Causa:** values padrão aceitos sem revisão.
- **Correção:** nenhuma registrada nas notas.
- **Recomendação:** senha gerada no Key Vault e entregue por External Secrets, ou SSO com Entra ID, e nenhuma UI de operação com IP público.

### 9.4 Guias de logs e APM descolados da aplicação

- **Sintoma:** queries em `ContainerLog` e diagnóstico pelos pods `omsagent`; o guia de APM usava `setup().start()` do SDK `applicationinsights`, variáveis `REACT_APP_*` num frontend Vite e imagens separadas de backend e frontend, quando a app real era uma imagem única servida pelo Express; o SDK de APM não chegou a ser integrado.
- **Causa:** guias genéricos escritos sem olhar o código.
- **Correção:** nenhuma registrada nas notas.
- **Recomendação:** partir da aplicação real: OpenTelemetry com `@azure/monitor-opentelemetry` no backend, variáveis `import.meta.env.VITE_*` resolvidas no build do Vite e sampling definido junto com o orçamento de ingestão.
- **Desatualizado (out/2026):** o Container Insights roda sobre o Azure Monitor Agent (pods `ama-logs`) e o esquema recomendado é `ContainerLogV2`; o SDK Node.js 3.x do Application Insights é baseado em OpenTelemetry; `ReactDOM.render` está depreciado desde o React 18.

## 10. Service mesh

### 10.1 Rótulo de injeção que o add-on ignora

- **Sintoma:** depois de `az aks mesh enable`, o namespace foi rotulado com `istio-injection=enabled` e a documentação passou a listar mTLS entre pods como implementado.
- **Causa:** o add-on Istio do AKS exige o rótulo de revisão `istio.io/rev=asm-X-Y`; com `istio-injection=enabled` a injeção é ignorada no namespace.
- **Correção:** nenhuma registrada nas notas, que também não registram a verificação do sidecar.
- **Recomendação:** ler a revisão com `az aks show --query 'serviceMeshProfile.istio.revisions'`, rotular, fazer `kubectl rollout restart` e confirmar o container `istio-proxy` antes de afirmar mTLS; planejar o upgrade canário de revisões.

### 10.2 Exemplos do Istio upstream aplicados ao add-on

- **Sintoma:** comandos com `svc/istio-ingressgateway` e Gateway com seletor `istio: ingressgateway`, enquanto o add-on publica `aks-istio-ingressgateway-external` no namespace `aks-istio-ingress` (só o exemplo do roadmap de STRICT usava esse seletor); a Telemetry API não era suportada no add-on, segundo a nota.
- **Causa:** exemplos copiados da documentação upstream.
- **Correção:** nenhuma registrada nas notas.
- **Recomendação:** tratar o add-on como produto próprio, conferindo nomes, labels e limitações na documentação do AKS, e validar com `istioctl analyze` apontando para o namespace `aks-istio-system`.
- **Desatualizado (out/2026):** a descrição de Pilot, Citadel e Galley como componentes separados é anterior ao istiod (2020); `consecutiveErrors` deu lugar a `consecutive5xxErrors`; `istioctl authn tls-check` não existe mais.

### 10.3 PERMISSIVE para acomodar uma entrada fora do mesh

- **Sintoma:** mTLS em PERMISSIVE para aceitar tráfego do NGINX e do gateway sem sidecar; o manifesto de exemplo se chamava `mtls-strict.yaml` e aplicava PERMISSIVE.
- **Causa:** a entrada não fazia parte do mesh.
- **Correção:** nenhuma; STRICT ficou no roadmap.
- **Recomendação:** decidir se o mesh se paga num cluster pequeno, já que cada sidecar consome CPU e memória; se ficar, entrada pelo gateway do mesh e STRICT por namespace, com a troca testada.

## 11. GitOps

### 11.1 Dois caminhos de deploy

- **Sintoma:** um workflow aplicava manifests com `kubectl apply`, atualizações eram feitas com `kubectl delete pods -n dx02 --all` para puxar `latest`, e uma Application do Argo CD com `prune` e `selfHeal` cuidava dos manifests do dx02.
- **Causa:** GitOps adicionado sem retirar o deploy imperativo.
- **Correção:** nenhuma registrada nas notas.
- **Recomendação:** um único dono por recurso: o CI publica a imagem e atualiza tag ou digest no Git, o Argo CD sincroniza e o rollback é um `git revert`.

### 11.2 Argo CD exposto e sem versão fixa

- **Sintoma:** `argocd-server` como LoadBalancer em HTTP com IP público, login admin com senha vinda de input, webhook do GitHub para `http://<PUBLIC_IP>/api/webhook`, instalação pelo manifest v2.13.3 e CLI baixada de `latest`.
- **Causa:** foco em ver a UI funcionando.
- **Correção:** nenhuma registrada nas notas.
- **Recomendação:** sem IP público (port-forward, ou SSO com Entra atrás do gateway com TLS), admin local desabilitado depois do SSO, versões fixadas e webhook com secret sobre HTTPS, ou polling.
- **Desatualizado (out/2026):** a linha 2.x do Argo CD está fora de suporte; a atual é a 3.x.

## 12. Políticas

### 12.1 Gatekeeper sem caminho para deny

- **Sintoma:** três políticas, com labels e limits em `dryrun` e containers privilegiados em `deny`; a auditoria mostrou cinco pods sem limits; exceções para kube-system, gatekeeper-system e monitoring.
- **Causa:** rollout gradual sem prazo nem dono.
- **Correção:** nenhuma registrada nas notas.
- **Recomendação:** dryrun, depois warn, depois deny com data; exceções explícitas e revisadas; o namespace do Chaos Mesh não estava na lista e o chaos-daemon roda privilegiado, um conflito a resolver antes de instalar.

### 12.2 NetworkPolicy de exemplo que não funcionaria

- **Sintoma:** o exemplo liberava entrada a partir de um namespace com label `name: ingress-nginx`, que não existe por padrão, e saída para pods `app: sql-server`, quando o banco era PaaS fora do cluster.
- **Causa:** exemplo genérico sem teste.
- **Correção:** nenhuma registrada nas notas.
- **Recomendação:** selecionar namespaces por `kubernetes.io/metadata.name`, liberar saída para PaaS por `ipBlock` da subnet do endpoint privado e DNS para o kube-dns, e testar com um pod efêmero antes de aplicar deny-all.

## 13. Chaos engineering

### 13.1 Experimento sem hipótese nem métrica

- **Sintoma:** as queries para medir os experimentos (`http_requests_total`, `http_request_duration_seconds_bucket`) dependiam de métricas que a app não expunha; o cenário "all-experiments" juntava pod-kill a cada 2 minutos, 200 ms de latência, CPU a 80% e 256 MB de memória em `prd` por 10 minutos.
- **Causa:** ferramenta escolhida antes da hipótese e do SLI.
- **Correção:** nenhuma registrada nas notas.
- **Recomendação:** hipótese escrita, SLI medido, um tipo de falha por vez, condição de aborto e um ambiente que não seja o de produção.

### 13.2 Pré-requisitos e "custo zero" do Chaos Mesh

- **Sintoma:** reinstalação falhando com `CRDs already exist`; o dry run instalava o Chaos Mesh no cluster mesmo sem executar experimento; um 403 no Chaos Studio tinha como solução sugerida mais Contributor na subscription; o custo foi anunciado como zero.
- **Causa:** limpeza incompleta, privilégio usado como atalho e consumo de recursos ignorado.
- **Correção:** `helm uninstall`, exclusão do namespace e das CRDs do chaos-mesh antes de reinstalar.
- **Recomendação:** no AKS o runtime é containerd, então o chart precisa de `chaosDaemon.runtime=containerd` e `chaosDaemon.socketPath=/run/containerd/containerd.sock`; o daemon privilegiado em todo nó consome CPU e memória e precisa de exceção explícita nas políticas.

## 14. Backup e recuperação

### 14.1 DR apoiado numa premissa falsa

- **Sintoma:** a estratégia tratava o banco em westus2 como "redundância geográfica embutida" e contava com geo-restore, mas o guia de criação escolhia backup storage localmente redundante.
- **Causa:** região imposta pela oferta lida como desenho de DR.
- **Correção:** nenhuma registrada nas notas.
- **Recomendação:** geo-restore depende de backup storage geo-redundante; DR se desenha, se testa e se mede (RTO e RPO observados, não metas copiadas).

### 14.2 Plano de backup para coisas que não existiam

- **Sintoma:** PITR "configurável de 7 a 30 dias" num banco Basic; snapshots planejados para PVs de Prometheus e Grafana que rodavam sem persistência; PV de restore com volume in-tree `azureDisk`; orientação de esperar o primeiro full "semanal".
- **Causa:** documento genérico não confrontado com o deploy.
- **Correção:** nenhuma registrada nas notas.
- **Recomendação:** conferir cada item contra o que existe; o tier Basic aceita no máximo 7 dias de PITR; o primeiro backup completo é agendado logo após a criação do banco; restaurar disco com PV CSI (`disk.csi.azure.com`).
- **Desatualizado (out/2026):** o plugin in-tree `azureDisk` foi removido no Kubernetes 1.27.

### 14.3 Restore do state com nomes errados

- **Sintoma:** os comandos de restore do state usavam container e blob diferentes dos do backend real e listavam snapshots em vez de versões; o bootstrap configurava 7 dias de soft delete e o documento de backup prometia 30.
- **Causa:** comandos escritos sem ler a configuração do backend.
- **Correção:** nenhuma registrada nas notas.
- **Recomendação:** derivar os comandos do bloco `backend`, definir versioning e soft delete no bootstrap e ensaiar o restore do state uma vez por ciclo do lab.

## 15. Scans de segurança

### 15.1 Ferramentas e actions sem versão fixa

- **Sintoma:** `aquasecurity/trivy-action@master`, `SonarSource/sonarcloud-github-action@master`, tfsec, imagem `owasp/zap2docker-stable` e `-Dsonar.login` no scanner.
- **Causa:** exemplos copiados com a referência mais curta.
- **Correção:** nenhuma registrada nas notas.
- **Recomendação:** actions fixadas por SHA de commit e atualizadas por Dependabot; Trivy para imagem e IaC, Checkov e gitleaks no CI sem credenciais.
- **Desatualizado (out/2026):** o tfsec foi incorporado ao Trivy (`trivy config`); o SonarCloud virou SonarQube Cloud e a action recomendada é `SonarSource/sonarqube-scan-action`, com `sonar.token` no lugar de `sonar.login`; a imagem do ZAP passou a ser `ghcr.io/zaproxy/zaproxy:stable`.

### 15.2 Scans que não bloqueavam nada

- **Sintoma:** o `trivy-action` rodava sem `exit-code`, cujo padrão é 0, enquanto o fluxo documentado prometia bloquear o deploy; o tx02 tinha security rating C e 0% dos hotspots revisados no SonarCloud; o README exibia badges estáticos de "Quality Gate Passed" com o gate ainda "Not computed"; o guia de IaC recomendava ignore inline de TLS 1.0 justificado como "Free tier limitation".
- **Causa:** scans adicionados como relatório, não como gate.
- **Correção:** nenhuma registrada nas notas.
- **Recomendação:** build, scan com `exit-code: 1` e só então push, falhando em CRITICAL e HIGH; badges dinâmicos; quality gate como check obrigatório; ignore só com justificativa técnica e prazo.

### 15.3 Remediações que trocam um problema por outro

- **Sintoma:** página em branco resolvida com `contentSecurityPolicy: false` no helmet; headers de segurança via `configuration-snippet` do NGINX, incluindo `X-XSS-Protection`; `git filter-branch` como remédio para segredo no histórico; DAST apontado para o IP público em HTTP.
- **Causa:** correção do sintoma imediato.
- **Correção:** o CSP ficou desligado.
- **Recomendação:** num site só HTTP, a diretiva `upgrade-insecure-requests` do CSP padrão do helmet é causa comum de página em branco, então ajuste a diretiva em vez de desligar o CSP; segredo vazado se rotaciona primeiro e depois se limpa o histórico com `git filter-repo`; DAST contra o hostname com TLS.
- **Desatualizado (out/2026):** `X-XSS-Protection` é obsoleto nos navegadores; as imagens usavam `node:18-alpine` (fim de vida em abril de 2025) e `node:20` (fim de vida em abril de 2026).

## 16. Limpeza e recursos órfãos

### 16.1 O destroy não alcança o que o Terraform não criou

- **Sintoma:** gateway, WAF policy, IP público e subnet criados pelo workflow de segurança fora do Terraform; banco criado no portal, que só entrava no state se o import com `|| true` funcionasse; IPs e load balancers criados por Services no grupo `MC_<RG>_<AKS>_<REGION>`; CRDs do Chaos Mesh; a orientação era rodar destroy antes de cada novo apply ou `az group delete --name <RG> --yes --no-wait`.
- **Causa:** vários donos para a mesma infraestrutura.
- **Correção:** destroy e exclusão manual de grupos de recursos.
- **Recomendação:** tudo nasce pelo Terraform ou pelo GitOps; depois do destroy, verificar sobras com `az group list` e `az resource list` filtrando pela tag do lab, olhando IPs públicos, discos, snapshots, zonas DNS privadas, workspaces e o NetworkWatcherRG que a Azure cria automaticamente.

### 16.2 Exclusão assíncrona e nomes presos

- **Sintoma:** `--no-wait` devolvia o controle antes de a exclusão terminar; o nome do SQL server ficou preso por 5 a 10 minutos; o DNS dinâmico seguia apontando para o IP antigo até ser atualizado à mão.
- **Causa:** operações assíncronas e retenção de nomes após a exclusão.
- **Correção:** esperar e repetir à mão.
- **Recomendação:** `az group wait --name <RG> --deleted` antes da verificação de sobras; considerar o soft delete que retém nomes (Key Vault, workspace do Log Analytics) ao planejar recriações; remover registros DNS no destroy para não deixar apontamento solto.

## 17. Números de custo das notas

Preços de referência da época (dezembro de 2025 a janeiro de 2026), tirados das estimativas das notas; não servem como orçamento atual.

| Item | Valor nas notas |
|---|---|
| AKS com 2 nós Standard_D2s_v3 | cerca de US$ 150/mês |
| PostgreSQL Standard_D2s_v3 (planejado, nunca criado) | cerca de US$ 100/mês |
| Load Balancer Basic | cerca de US$ 20/mês |
| Storage do state | de US$ 0,01 a US$ 2/mês, conforme o guia |
| Total da base em modo AKS | cerca de US$ 272/mês (modo VM: cerca de US$ 30/mês) |
| Plano de janeiro: 3 nós Standard_B2s | US$ 30 a 50/mês |
| Plano de janeiro: rede e Private Endpoint | US$ 5 a 10/mês e US$ 3 a 5/mês |
| Plano de janeiro: total declarado | US$ 38 a 65/mês, com control plane do AKS, PostgreSQL B1ms e ACR Basic a US$ 0 |
| Application Gateway WAF_v2 com 2 instâncias | cerca de US$ 246/mês de base, US$ 0,008/GB processado, US$ 250 a 350/mês na média |
| IP público do gateway | cerca de US$ 4/mês |
| Application Gateway Standard_v2 sem WAF | cerca de US$ 125/mês |
| ingress-nginx com LoadBalancer | US$ 20 a 30/mês |
| Log Analytics | 5 GB/mês grátis, US$ 2,30/GB, retenção extra a US$ 0,10/GB/mês |
| Logs estimados (cerca de 24 GB/mês) | cerca de US$ 44/mês, ou US$ 20 a 40 com filtros |
| Application Insights (sampling de 50%, cerca de 2,2 GB/mês) | US$ 0 declarado; availability test a US$ 1,20 por teste/mês e multi-step a US$ 4,80 por teste/mês |
| Azure SQL Basic (backup incluído) | cerca de US$ 5/mês |
| LTR do SQL (cerca de 20 GB) | cerca de US$ 0,50/mês (US$ 0,02/GB) |
| Snapshots de disco (50 GB) | cerca de US$ 2,50/mês (US$ 0,05/GB) |
| Chaos Mesh | US$ 0, mais cerca de US$ 5/mês de logs |
| Crédito do Free Trial | R$ 1.078,95 (cerca de US$ 200) por 30 dias, estimado em 25 dias de modo AKS |
| Oferta gratuita do Azure SQL | 100.000 vCore-segundos/mês |

O que continua valendo: o crédito acabava em semanas; a entrada com WAF custava tanto quanto o resto do lab somado, ou mais; ACR Basic não é gratuito (cobrança diária); Basic Load Balancer e IP público Basic foram aposentados em 30/09/2025.

No v2, o maior item é o Application Gateway for Containers com WAF: cerca de US$ 0,28 por hora (Azure Retail Prices API, eastus, 2026-10-11), considerando 1 frontend, 1 associação e cerca de 1 capacity unit, o que dá cerca de US$ 204 por mês se ficar ligado o mês inteiro.
