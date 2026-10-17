# Continuidade de dados — R9 (Azure)

## Prova adicional de PVC pelo Velero

O CI local executa `scripts/local/volume-restore-drill.sh`: grava bytes num volume
`local` do kind por um Pod restrito, exige `PodVolumeBackup Completed`, remove o
namespace/PVC/PV e os dados originais, e restaura. Só passa com PVC de novo UID,
`PodVolumeRestore Completed` e SHA256 idêntico. Restaurar apenas um ConfigMap ou um
PVC vazio não atende a esse check. A execução pesada fica no GitHub Actions.

O FSB precisa de root/hostPath no namespace Velero local; o servidor continua non-root
e a aplicação mantém Pod Security `restricted`. A senha aleatória do repositório
Kopia é criada antes do primeiro backup e preservada nas reinstalações. Não publique
essa senha nem os backups de Secrets. Cloud usa seu driver CSI e requer ensaio
autorizado próprio; o resultado kind não certifica snapshots gerenciados.

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

## Preparação do standby, backups e state

1. Habilite o perfil DR e, no bootstrap, `state_replication_type="RAGRS"`. Inspecione
   o plano de conversão de um backend existente; nunca aceite substituir o bucket/
   container que contém seu state. O state mantém versões, soft delete e lock.
2. Configure o secret do environment `LAB_VELERO_REPOSITORY_PASSWORD` com 64 caracteres
   hexadecimais aleatórios e preserve uma cópia privada fora das regiões. O mesmo
   segredo protege o Kopia nos dois clusters. Não o rotacione depois do primeiro
   backup: isso impediria ler o repositório existente. A instalação recusa divergência.
3. O apply protegido sincroniza **os valores atuais** do Key Vault primário, mudando
   somente o FQDN do banco no destino. Reexecute após rotações. Plan não lê valores;
   o acesso de apply já vem do Secrets Officer restrito ao resource group do lab.
4. Instale com `platform/install.sh --profile full --github-owner OWNER --target secondary`.
   O AKS secundário usa `gitops/azure-dr`, recursos de telemetria regionais e seu
   próprio backup. O destino `primary-recovery` lê o endpoint Blob secundário do
   storage RAGRS primário, com **Storage Blob Data Reader apenas naquele container**.
   As duas subnets usam Microsoft.Storage.Global; nenhuma faixa pública foi liberada.
5. Confira conclusão/lag da geo replicação e Last Sync Time antes de aceitar o backup.
   RAGRS é assíncrono e não garante RPO zero. Os schedules têm nomes diferentes para
   não colidir no catálogo. Kopia coleta chunks por referência: lifecycle por idade
   aplica-se só a `backups/`, nunca aos chunks vivos do repositório.
6. O cert-manager do standby cria issuer/certificate sem esperar HTTP-01 no DNS que
   ainda aponta para o primário. Antes de promover tráfego, restaure apenas o Secret
   TLS marcado a partir do backup importado:

```yaml
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: standby-tls
  namespace: velero
spec:
  backupName: REPLACE_WITH_IMPORTED_BACKUP_NAME
  includedNamespaces: [dx02v2]
  includedResources: [secrets]
  labelSelector:
    matchLabels:
      lab.continuity/tls: "true"
```

Exija Restore Completed, confirme validade/SAN e não publique o material TLS. O
certificado precisa estar no backup antes do incidente. A renovação HTTP-01 usa o
novo Gateway depois da troca de DNS. Faça o smoke do DX no endereço do standby;
só após fencing, promoção e aceite dos dados use `active_region=secondary` /
`LAB_ACTIVE_REGION` para mover o CNAME. Esse input não promove o banco.

Velero protege objetos e bytes dos PVCs com FSB/data mover; o namespace velero
permite root/hostPath para ler os mounts do kubelet, mantendo os namespaces da app
restritos. O checksum do restore local é prova separada do backup nativo PostgreSQL.
`LabBackupTooOldOrMissing` (30 h) e `LabRestoreFailed` chegam ao Alertmanager/Slack
configurado. O Azure Monitor registra o alerta nativo de lag (>60 s em 5 min);
associe um action group no exercício cloud para notificações fora do portal.

Na perda regional, leia a versão escolhida do state pelo endpoint secundário para
um diretório privado, confira lineage/serial e faça fencing de qualquer apply antigo.
Nunca use dois backends graváveis ao mesmo tempo ou publique o state em artifacts.
O destroy inventaria ambos os AKS antes do Terraform; revise locks e retenções antes
de liberar a exclusão. A recuperação gerenciada, emissão ACME e egress ainda não
foram homologados na Azure v2.

## Referências operacionais

- [HA e restrições de SKU/região](https://learn.microsoft.com/azure/postgresql/high-availability/concepts-high-availability)
- [Backup, PITR e geo restore](https://learn.microsoft.com/azure/postgresql/backup-restore/concepts-backup-restore)
- [Rede privada e replicação regional](https://learn.microsoft.com/azure/postgresql/network/concepts-networking-private)
- [Locks de recursos](https://learn.microsoft.com/azure/azure-resource-manager/management/lock-resources)
