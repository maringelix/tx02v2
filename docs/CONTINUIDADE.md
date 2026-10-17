# Continuidade de dados — R9 (Azure)

O código de HA/DR usa testes Terraform com provedores simulados. **Nenhum restore, promoção ou
failover foi executado na Azure na v2.** O exercício Docker usa PostgreSQL real, mas não mede a
redundância de zona, o atraso geográfico nem as restrições de oferta de uma assinatura Azure.

| `postgres_profile` | Principal | Destino DR |
|---|---|---|
| `core` (padrão) | Burstable B1ms, 7 dias de backups/PITR nativo, sem standby | nenhum |
| `ha` | General Purpose `GP_Standard_D2ads_v5`, standby ZoneRedundant, retenção 7–35 dias | nenhum |
| `dr` | como HA, mais backup georredundante | réplica PostgreSQL privada, AKS, VNet, ACR, Key Vault, App Configuration, AGC/WAF e Velero em outra região |

A receita de HA/DR valida o par `eastus2`/`centralus`. Verifique SKU, zonas, cotas e suporte à oferta
da sua assinatura antes do apply. A validação offline não prova capacidade disponível. O `core`
mantém o custo original; HA e DR são escolhas explícitas e custam computação/armazenamento adicionais.

`postgres_backup_retention_days` parametriza o PITR nativo entre 7 e 35 dias. Backups georredundantes
são selecionados **na criação**: mudar `postgres_geo_backup` ou entrar em `dr` a partir de um servidor
sem geo backup pode recriar o banco. Revise o plano e migre dados primeiro em um ambiente com dados
reais. Geo restore usa o último backup disponível na região pareada, com RPO potencial de até uma
hora; não oferece PITR geográfico. A réplica DR também é assíncrona, portanto a perda depende do lag.

`postgres_delete_lock=true` cria um lock Azure `CanNotDelete` somente no servidor principal. Isso
exige permissão para locks (Owner ou papel específico); o Contributor do CI não ganha novos poderes.
Faça a operação com uma identidade autorizada e revise a remoção antes do teardown. O Terraform
pode remover o lock que ele mesmo gerencia durante um destroy: ele protege exclusões acidentais
fora desse fluxo, não substitui revisão do plano nem backup. O padrão `false` permite teardown.

## Provas locais e de CI

`terraform -chdir=terraform/envs/lab test` verifica a composição das duas regiões, SKU HA, backups,
rede privada, peering, DNS cruzado, permissões por recurso/repositório e sujeitos exatos de Workload
Identity. O teste recusa perfil inválido, Burstable em HA, região repetida e subnets sobrepostas.

O GitHub Actions executa `make e2e`. A sonda `scripts/local/pitr-drill.sh` produz backup físico com
manifesto, arquiva WAL num volume separado, confirma um registro antes do restore point, apaga-o
depois e recupera o ponto escolhido numa instância isolada. `pg_verifybackup` precisa rejeitar uma
cópia corrompida; a consulta precisa retornar os registros corretos e respeitar o limite local de
180 segundos. O DX02v2 coordena a prova de reconexão da aplicação, PVC/Velero e failover/failback A/B.
Restauração de ConfigMap sozinha não comprova recuperação de dados.

## Restore isolado e troca de endpoint

1. Registre a janela PITR, último backup completo, versão/migrações do app, marcador de transação,
   limite de perda e custo de uma instância temporária. Congele escrita se houver corrupção ativa.
2. Faça PITR para **novo** Flexible Server na mesma região, usando a
   [documentação de backup/restore](https://learn.microsoft.com/azure/postgresql/backup-restore/concepts-backup-restore).
   Para perda regional, use a réplica DR ou geo restore na região pareada; são mecanismos diferentes.
3. Confira acesso privado, TLS, contagens, chaves e marcadores. Registre perda observada e segundos
   até uma transação válida. Valide a compatibilidade das migrações antes de usar a versão do app.
4. Atualize o segredo de banco no Key Vault e aguarde o ESO; reinicie o rollout da API, valide
   readiness, leitura e escrita idempotente. Só depois libere tráfego. Se a prova falhar, mantenha
   o endpoint anterior e preserve as instâncias para comparar dados.

## Failover regional e failback

O operador precisa de aprovação humana explícita para cada ação cloud. Declare o incidente e
comprove o fencing do escritor primário: bloqueie deploys e entrada de escrita e confirme que o
servidor antigo não aceita transações. **Se não puder garantir um único escritor, recuse a promoção.**
Registre lag, último marcador replicado e perda aceitável antes de promover. A replicação privada
usa peering das duas VNets, DNS nas duas direções e somente TCP/5432 entre as subnets PostgreSQL.

Siga a [promoção de réplica](https://learn.microsoft.com/azure/postgresql/read-replica/concepts-read-replicas-geo)
para a versão de CLI instalada. Após promoção, revise a topologia Terraform antes de qualquer apply;
não reaplique cegamente `create_mode=Replica` sobre um servidor promovido. A região secundária tem
seu próprio endpoint App Configuration (output `dr_appconfig_endpoint`), registry, Key Vault e AGC.
Copie imagens por digest e segredos/configuração antes do incidente. Valide dados, backup/PITR da
nova principal e uma escrita idempotente antes de encaminhar tráfego ao AGC secundário.

No retorno, recrie/ressincronize a região original a partir do escritor atual. Espere o lag aceito,
congele escrita, aplique fencing da região secundária e faça a promoção planejada. Revalide dados
e roteamento antes de reabrir. Preserve hashes/evidências, registre RPO/RTO e destrua recursos
temporários depois do aceite. Estado Terraform e backups precisam de cópia recuperável fora da
região afetada; o state padrão do bootstrap é versionado, mas LRS não é uma réplica regional.

## Fontes

- [HA e restrições de SKU/região](https://learn.microsoft.com/azure/postgresql/high-availability/concepts-high-availability)
- [Backup, PITR e geo restore](https://learn.microsoft.com/azure/postgresql/backup-restore/concepts-backup-restore)
- [Rede privada e replicação regional](https://learn.microsoft.com/azure/postgresql/network/concepts-networking-private)
- [Locks de recursos](https://learn.microsoft.com/azure/azure-resource-manager/management/lock-resources)
